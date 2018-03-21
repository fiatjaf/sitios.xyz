package main

import (
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/kr/s3"
	"github.com/minio/minio-go"
	"github.com/minio/minio-go/pkg/policy"
)

var AWS_KEY_ID = os.Getenv("AWS_KEY_ID")
var AWS_SECRET_KEY = os.Getenv("AWS_SECRET_KEY")

var ms3, _ = minio.New(
	"s3.amazonaws.com",
	AWS_KEY_ID,
	AWS_SECRET_KEY,
	true,
)

func ensureEmptyBucket(bucketName string) error {
	exists, err := ms3.BucketExists(bucketName)
	if err != nil {
		return err
	}

	if !exists {
		err = ms3.MakeBucket(bucketName, "us-east-1")
		if err != nil {
			return err
		}
	}

	err = ms3.SetBucketPolicy(bucketName, "", policy.BucketPolicyReadOnly)
	if err != nil {
		return err
	}

	err = makeBucketAWebsite(bucketName)
	if err != nil {
		return err
	}

	emptyBucket(bucketName)
	return nil
}

func removeBucket(bucketName string) error {
	emptyBucket(bucketName)

	if err := ms3.RemoveBucket(bucketName); err != nil {
		exists, err := ms3.BucketExists(bucketName)
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
		for object := range ms3.ListObjects(bucketName, "", true, doneCh) {
			if object.Err != nil {
				log.Error().
					Err(object.Err).
					Str("obj", object.Key).
					Msg("error listing object")
			}
			objectsCh <- object.Key
		}
	}()
	errorCh := ms3.RemoveObjects(bucketName, objectsCh)

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
			_, err = ms3.FPutObject(bucketName, objectname, filename,
				minio.PutObjectOptions{
					ContentType: mimetype(filename),
				})
			if err != nil {
				return nil
			}

			return nil
		})
}

func mimetype(filename string) string {
	return mime.TypeByExtension(filepath.Ext(filename))
}

func makeBucketAWebsite(bucketName string) error {
	keys := s3.Keys{
		AccessKey: AWS_KEY_ID,
		SecretKey: AWS_SECRET_KEY,
	}
	data := strings.NewReader(`
<WebsiteConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <IndexDocument>
    <Suffix>index.html</Suffix>
  </IndexDocument>
  <ErrorDocument>
    <Key>error.html</Key>
  </ErrorDocument>
</WebsiteConfiguration>
`)
	r, _ := http.NewRequest(
		"PUT", "http://"+bucketName+".s3.amazonaws.com/?website", data)
	r.ContentLength = int64(data.Len())
	r.Header.Set("Date", time.Now().UTC().Format(http.TimeFormat))
	s3.Sign(r, keys)
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		return err
	}

	log.Print(resp.StatusCode)
	return nil
}
