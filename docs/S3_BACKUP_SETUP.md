# S3 Backup Setup

Nightly, a small function copies every table of the production database to your own S3 bucket as compressed JSON files, one folder per day. Keeping a copy with a different company than the database is the point: if Supabase ever has a bad day, your data is somewhere else.

## Your steps, about 10 minutes, in the AWS console

### 1. Bucket

1. Open S3, click **Create bucket**.
2. Name: `duebook-backups` (bucket names are global, so if it is taken use `duebook-backups-sparkingasia`).
3. Region: **Asia Pacific (Mumbai) ap-south-1**, same as the database.
4. Leave **Block all public access** turned on.
5. Under **Bucket Versioning** choose **Enable**. This keeps old copies even if a file is overwritten or deleted.
6. Create the bucket.

### 2. Lifecycle rule, so old backups do not pile up

1. Open the bucket, **Management** tab, **Create lifecycle rule**.
2. Name: `expire-old-backups`. Apply to all objects.
3. Tick **Expire current versions of objects** and set 90 days. Tick **Permanently delete noncurrent versions** and set 30 days.
4. Save.

### 3. A user that can touch only this bucket

1. Open IAM, **Users**, **Create user**. Name: `duebook-backup`. Do not give console access.
2. On the permissions step choose **Attach policies directly**, then **Create policy**, switch to the **JSON** tab, and paste this, replacing `duebook-backups` if you used a different bucket name:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListTheBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::duebook-backups"
    },
    {
      "Sid": "ReadWriteObjects",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject"],
      "Resource": "arn:aws:s3:::duebook-backups/*"
    }
  ]
}
```

3. Name the policy `duebook-backup-only`, create it, go back to the user creation tab, refresh the policy list, tick `duebook-backup-only`, and finish creating the user.
4. Open the user, **Security credentials** tab, **Create access key**. Choose **Application running outside AWS**. Download or copy the **Access key** and the **Secret access key**. The secret is shown once.

### 4. Hand the keys to Supabase, never to chat or GitHub

1. Open https://supabase.com/dashboard/project/ohrnkvzemgfrxcuknamh/functions/secrets (that is the production project).
2. Add `BACKUP_S3_ACCESS_KEY` with the access key.
3. Add `BACKUP_S3_SECRET_KEY` with the secret access key.
4. Add `BACKUP_S3_BUCKET` with the bucket name.
5. Add `BACKUP_S3_REGION` with `ap-south-1`.

Do the same on the dev project (https://supabase.com/dashboard/project/jepcsftdjejjzhfjnavy/functions/secrets) if you want dev backed up too. Not required.

### 5. Tell me

Reply with the bucket name and region. I deploy the backup function, schedule it for 3 am Pakistan time, run it once by hand, and then do a restore drill into the dev project so we know the files are usable.

## What the backup contains

Every table in the public schema, including the audit log, as `gzip` compressed JSON, under `duebook/<project>/<YYYY-MM-DD>/<table>.json.gz`. Auth users are exported as ids, emails and names, without passwords (Supabase never exposes those; a restore recreates accounts and people sign in again).
