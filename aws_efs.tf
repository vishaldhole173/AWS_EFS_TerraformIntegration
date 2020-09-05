provider "aws" {
  region  = "ap-south-1"
}
resource "aws_vpc" "main" {
  cidr_block       = "192.168.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "myvpc1"
  }
}
resource "aws_subnet" "main1" {
  vpc_id     = "${aws_vpc.main.id}"
  cidr_block = "192.168.0.0/24"
  map_public_ip_on_launch = true
  availability_zone = "ap-south-1a"


  tags = {
    Name = "subnet1"
  }
}
resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.main.id}"

  tags = {
    Name = "mygw1"
  }
}
resource "aws_route_table" "r" {
  vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }

  tags = {
    Name = "routetable"
  }
}
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.main1.id
  route_table_id = aws_route_table.r.id
}
  resource "aws_s3_bucket" "b" {
  bucket = "vishalbucket"
  acl    = "public-read"
 tags = {
  Name = "lwbucket"
}

}
resource "aws_s3_bucket_object" "object" {
  bucket = aws_s3_bucket.b.id
  key    = "cloud.jpg"
}

locals{
  s3_origin_id = "aws_s3_bucket.b.id"
  depends_on = [aws_s3_bucket.b]
}
resource "aws_security_group" "sg1" {
  name        = "securitygroup1"
  description = "Allow NFS"
  vpc_id      = "${aws_vpc.main.id}"

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "NFSgroup1"
  }
}
resource "aws_efs_file_system" "myefs" {
  creation_token = "myefs"
  performance_mode = "generalPurpose"

  tags = {
    Name = "myefs1"
  }
}

resource "aws_efs_mount_target" "myefs-mount" {
  file_system_id = aws_efs_file_system.myefs.id
  subnet_id = aws_subnet.main1.id
  security_groups = [ aws_security_group.sg1.id ]
}
resource "aws_instance" "webserver" {
  depends_on = [ aws_efs_mount_target.myefs-mount ]
  ami = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "mykey11"
  subnet_id = aws_subnet.main1.id
  vpc_security_group_ids = [ aws_security_group.sg1.id ]
  
  tags = {
    Name = "WebServer"
  }
}
resource "null_resource" "nullremote1" {
  depends_on = [
    aws_instance.webserver
  ]
  connection {
    type = "ssh"
    user= "ec2-user"
    private_key = file("mykey11.pem")
    host = aws_instance.webserver.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git amazon-efs-utils nfs-utils -y",
      "sudo setenforce 0",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
      "sudo mount -t efs ${aws_efs_file_system.myefs.id}:/ /var/www/html",
      "sudo echo '${aws_efs_file_system.myefs.id}:/ /var/www/html efs defaults,_netdev 0 0' >> /etc/fstab",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/onkar1-git/AWS_EFS.git /var/www/html/"
    ]
  }
}
resource "aws_cloudfront_origin_access_identity" "identity" {
  comment = "Some comment"
}
output "origin_access_identity" {
  value = aws_cloudfront_origin_access_identity.identity
}
data "aws_iam_policy_document" "policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.b.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.identity.iam_arn}"]
    }
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.b.arn}"]
    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.identity.iam_arn}"]
    }
  }
}
resource "aws_s3_bucket_policy" "policy1" {
  bucket = aws_s3_bucket.b.id
  policy = data.aws_iam_policy_document.policy.json
}

resource "aws_cloudfront_distribution" "cloudfront1" {
    enabled             = true
    is_ipv6_enabled     = true
    wait_for_deployment = false
    origin {
        domain_name = "${aws_s3_bucket.b.bucket_regional_domain_name}"
        origin_id   = local.s3_origin_id
    s3_origin_config {
       origin_access_identity = "${aws_cloudfront_origin_access_identity.identity.cloudfront_access_identity_path}" 
        
}
}
    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id
      forwarded_values {
            query_string = false
        
            cookies {
               forward = "none"
            }
        }
        
        viewer_protocol_policy = "redirect-to-https"
        min_ttl                =  0
        default_ttl            =  3600
        max_ttl                =  86400
    }
    restrictions {
        geo_restriction {
            restriction_type = "none"
        }
    }
viewer_certificate {
        cloudfront_default_certificate = true
    }
}