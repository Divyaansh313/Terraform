provider "aws" {
  region = "ap-south-1"

}

resource "aws_security_group" "mysecuregroup" {
    name= "WebSecuregroup"
    description="security group for instance"
    vpc_id="vpc-b4d4cbdc"
    
    ingress{
      from_port=22
      to_port=22
      protocol="tcp"
      cidr_blocks=["0.0.0.0/0"]
      ipv6_cidr_blocks=["::/0"]
    }
     ingress{
      from_port=80
      to_port=80
      protocol="tcp"
      cidr_blocks=["0.0.0.0/0"]
      ipv6_cidr_blocks=["::/0"]
    }
    egress{
      from_port=0
      to_port=0
      protocol="-1"
      cidr_blocks=["0.0.0.0/0"] 
      ipv6_cidr_blocks=["::/0"] 
    }
  
}

resource "aws_instance" "webos" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "key111222"
  security_groups = [ "WebSecuregroup" ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/ASUS/Downloads/key111222.pem")
    host     = aws_instance.webos.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "WebOS1"
  }
}

resource "aws_ebs_volume" "EBSvol" {
  availability_zone = aws_instance.webos.availability_zone
  size              = 1
  tags = {
    Name = "WebEBS"
  }
}

resource "aws_volume_attachment" "EBSattach" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.EBSvol.id}"
  instance_id = "${aws_instance.webos.id}"
  force_detach = true
}

resource "null_resource" "RemoteAccess"  {

depends_on = [
    aws_volume_attachment.EBSattach,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/ASUS/Downloads/key111222.pem")
    host     = aws_instance.webos.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Divyaansh313/Terraform.git /var/www/html/"
    ]
  }
}

resource "aws_s3_bucket" "terraformbucketforwebsite" {
  bucket = "awswebbucketusingterraform"
  acl    = "private"
tags= {
Name = "WebBucket"
}
}


resource "aws_s3_bucket_object" "bucketobjectstore" {
  bucket = "awswebbucketusingterraform"
  key    = "waterfall.jpg"
  source = "C:/Users/ASUS/Documents/waterfall.jpg"
}

locals {
  s3_origin_id = "terra_s3_bucket_originID"
}


resource "aws_cloudfront_origin_access_identity" "terraform_origin_access" {
comment = "This is Terraform origin access identity"
}


resource "aws_cloudfront_distribution" "terraform_cloudfront" {
  origin {
    domain_name = aws_s3_bucket.terraformbucketforwebsite.bucket_regional_domain_name
    origin_id   = local.s3_origin_id


      s3_origin_config {
      origin_access_identity =aws_cloudfront_origin_access_identity.terraform_origin_access.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "cloudfront distribution terraform"
  default_root_object = "index.html"

default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
forwarded_values {
      query_string = false
cookies {
        forward = "none"
      }
    }

viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

     cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
      
    }
  }

viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "terraform_s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.terraformbucketforwebsite.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.terraform_origin_access.iam_arn]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.terraformbucketforwebsite.arn]

      principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.terraform_origin_access.iam_arn]
    }
  }
}


resource "aws_s3_bucket_policy" "terraform_bucket_policy" {
  bucket = aws_s3_bucket.terraformbucketforwebsite.id
  policy = data.aws_iam_policy_document.terraform_s3_policy.json
}

output "cloudfront_ip" {
 value=aws_cloudfront_distribution.terraform_cloudfront.domain_name
}


output "instance_ip" {
 value=aws_instance.webos.public_ip
}
