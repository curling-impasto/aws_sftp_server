
# create a random string for unique names
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

# Create an S3 bucket with AWS managed keys
resource "aws_s3_bucket" "sftp_bucket" {
  bucket = "${var.sftp_server_name}-bucket-${random_string.suffix.result}"
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  count  = length(var.lambda_role_arns) > 0 ? 1 : 0 # Only create if the list is non-empty
  bucket = aws_s3_bucket.sftp_bucket.id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Id" : "PolicyForSftpBucket",
    "Statement" : [
      {
        "Sid" : "ListAndGetPermissions",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : var.lambda_role_arns
        },
        "Action" : [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectAcl"
        ],
        "Resource" : [
          aws_s3_bucket.sftp_bucket.arn,
          "${aws_s3_bucket.sftp_bucket.arn}/*"
        ]
      },
      {
        "Sid" : "AllowSSLRequestsOnly",
        "Effect" : "Deny",
        "Principal" : "*",
        "Action" : "s3:*",
        "Resource" : [
          aws_s3_bucket.sftp_bucket.arn,
          "${aws_s3_bucket.sftp_bucket.arn}/*"
        ],
        "Condition" : {
          "Bool" : {
            "aws:SecureTransport" : "false"
          }
        }
      }
    ]
  })
}


# Enable encryption on S3
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_encryption" {
  bucket = aws_s3_bucket.sftp_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_iam_role" "sftp_user_role" {
  name = "${var.sftp_server_name}-${random_string.suffix.result}-role"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "transfer.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "sftp_user_policy" {
  name = "${var.sftp_server_name}-${random_string.suffix.result}-policy"
  role = aws_iam_role.sftp_user_role.name

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "${aws_s3_bucket.sftp_bucket.arn}",
                "${aws_s3_bucket.sftp_bucket.arn}/*"
            ]
        }
    ]
}
POLICY
}

# generate a Security group fgor vpc endpoint with inbound andf outbound rules
resource "aws_security_group" "sftp_endpoint_sg" {
  name        = "${var.sftp_server_name}-${random_string.suffix.result}-sg"
  description = "Allow inbound traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.public_subnet_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_cloudwatch_log_group" "transfer_log_group" {
  name_prefix       = "${var.sftp_server_name}-${random_string.suffix.result}-log"
  retention_in_days = 30
}

resource "aws_eip" "public_ip" {
  domain = "vpc"
}

# Create SFTP transfer family server
resource "aws_transfer_server" "transfer" {
  endpoint_type        = "VPC"
  security_policy_name = "TransferSecurityPolicy-2024-01"
  endpoint_details {
    vpc_id                 = var.vpc_id
    subnet_ids             = [var.subnet_id]
    security_group_ids     = [aws_security_group.sftp_endpoint_sg.id]
    address_allocation_ids = [aws_eip.public_ip.id]
  }
  protocols                        = ["SFTP"]
  force_destroy                    = true
  post_authentication_login_banner = "Welcome to Amdocs ${var.sftp_server_name} SFTP site"
  logging_role                     = aws_iam_role.sftp_user_role.arn
  structured_log_destinations = [
    "${aws_cloudwatch_log_group.transfer_log_group.arn}:*"
  ]
}

resource "aws_transfer_tag" "hostname" {
  resource_arn = aws_transfer_server.transfer.arn
  key          = "aws:transfer:customHostname"
  value        = var.custom_hostname
}


# Create an IAM Role for the SFTP user's transfer family directory
resource "aws_iam_role" "sftp_local_user_role" {
  count              = length(var.sftp_users)
  name               = "${var.sftp_users[count.index].username}-transfer-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "transfer.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Define the IAM role for replication
data "aws_iam_policy_document" "sftp_local_user_policy" {
  count = length(var.sftp_users)
  statement {
    sid    = "HomeDirObjectAccess"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObjectVersion",
      "s3:GetObjectACL",
      "s3:PutObjectACL"
    ]

    resources = [
      "${aws_s3_bucket.sftp_bucket.arn}/${var.sftp_users[count.index].username}/*"
    ]
  }
  statement {

    sid    = "AllowListingOfUserFolder"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = [
      "${aws_s3_bucket.sftp_bucket.arn}"
    ]
  }
}

# Create an IAM policy for the SFTP user's transfer family directory
resource "aws_iam_policy" "sftp_local_user_policy" {
  count  = length(var.sftp_users)
  name   = "${var.sftp_users[count.index].username}-transfer-policy"
  policy = data.aws_iam_policy_document.sftp_local_user_policy[count.index].json
}

# Attach the IAM user policy to the IAM role
resource "aws_iam_role_policy_attachment" "sftp_user_policy_attachment" {
  count      = length(var.sftp_users)
  role       = aws_iam_role.sftp_local_user_role[count.index].name
  policy_arn = aws_iam_policy.sftp_local_user_policy[count.index].arn

}


# Create SFTP users in transfer family server
resource "aws_transfer_user" "sftp_users" {
  count     = length(var.sftp_users)
  server_id = aws_transfer_server.transfer.id
  user_name = var.sftp_users[count.index].username
  role      = aws_iam_role.sftp_local_user_role[count.index].arn

  home_directory_type = "LOGICAL"
  home_directory_mappings {
    entry  = "/"
    target = "/${aws_s3_bucket.sftp_bucket.bucket}/${var.sftp_users[count.index].username}"
  }
}

# resource "aws_route53_record" "transfer_server_record" {
#   provider = aws.prod
#   zone_id = data.aws_route53_zone.public_zone.id
#   name    = var.custom_hostname
#   type    = "CNAME"
#   ttl     = 300
#   records = [aws_transfer_server.transfer.endpoint]
# }
