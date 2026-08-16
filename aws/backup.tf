data "aws_iam_policy_document" "backup-trust" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${local.account_name}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup-trust.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_vault" "data" {
  name = "${local.account_name}-data"

  tags = {
    Name = "${local.account_name}-data-backup"
  }
}

resource "aws_backup_plan" "data" {
  name = "${local.account_name}-data"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.data.name
    schedule          = "cron(0 3 * * ? *)"
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = 30
    }
  }

  tags = {
    Name = "${local.account_name}-data-backup"
  }
}

resource "aws_backup_selection" "data" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "${local.account_name}-data"
  plan_id      = aws_backup_plan.data.id

  resources = [aws_ebs_volume.data.arn]
}
