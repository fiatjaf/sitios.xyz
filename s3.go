package main

import (
	"mime"
	"os"
	"path/filepath"

	"github.com/minio/minio-go"
	"github.com/minio/minio-go/pkg/policy"
)

var s3, _ = minio.New(
	"s3.amazonaws.com",
	os.Getenv("AWS_KEY_ID"),
	os.Getenv("AWS_SECRET_KEY"),
	true,
)

func ensureEmptyBucket(bucketName string) error {
	exists, err := s3.BucketExists(bucketName)
	if err != nil {
		return err
	}

	if !exists {
		err = s3.MakeBucket(bucketName, "us-east-1")
		if err != nil {
			return err
		}
	}

	err = s3.SetBucketPolicy(bucketName, "", policy.BucketPolicyReadOnly)
	if err != nil {
		return err
	}

	emptyBucket(bucketName)
	return nil
}

func removeBucket(bucketName string) error {
	emptyBucket(bucketName)

	if err := s3.RemoveBucket(bucketName); err != nil {
		exists, err := s3.BucketExists(bucketName)
		if err != nil {
			return err
		}

		if !exists {
			// already deleted
			return nil
		}
	}

	return nil
}

func emptyBucket(bucketName string) {
	objectsCh := make(chan string)
	doneCh := make(chan struct{})

	go func() {
		defer close(objectsCh)
		for object := range s3.ListObjects(bucketName, "", true, doneCh) {
			if object.Err != nil {
				log.Error().
					Err(object.Err).
					Str("obj", object.Key).
					Msg("error listing object")
			}
			objectsCh <- object.Key
		}
	}()
	errorCh := s3.RemoveObjects(bucketName, objectsCh)

	// print errors received from RemoveObjects API
	for e := range errorCh {
		log.Warn().
			Err(e.Err).
			Str("obj", e.ObjectName).
			Str("bucket", bucketName).
			Msg("failed to remove object from bucket")
	}
}

func uploadFilesToBucket(bucketName, dirname string) error {
	return filepath.Walk(
		dirname, func(filename string, info os.FileInfo, err error) error {

			if err != nil {
				return err
			}
			if info.IsDir() {
				return nil
			}

			objectname, _ := filepath.Rel(dirname, filename)
			n, err := s3.FPutObject(bucketName, objectname, filename,
				minio.PutObjectOptions{
					ContentType: mimetype(filename),
				})
			if err != nil {
				return nil
			}

			log.Debug().
				Str("file", filename).
				Int("bytes", int(n)).
				Msg("successfully uploaded")
			return nil
		})
}

func mimetype(filename string) string {
	return mime.TypeByExtension(filepath.Ext(filename))
}
