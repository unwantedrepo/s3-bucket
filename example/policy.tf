data "aws_iam_policy_document" "ap_app" {
  statement {
    sid    = "AllowAppAccessViaAccessPoint"
    effect = "Allow"

    # Access Point policies SHOULD use wildcard principal
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    # Resource must be OBJECTS THROUGH ACCESS POINT
    resources = [
      "arn:aws:s3:${var.region}:${data.aws_caller_identity.current.account_id}:accesspoint/app/object/app/*"
    ]
    # Restrict to same AWS account
    condition {
      test     = "StringEquals"
      variable = "s3:DataAccessPointAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    # Restrict to specific IAM role
    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/app-role"
      ]
    }
  }
}