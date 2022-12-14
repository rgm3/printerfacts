let kms =
      https://xena.greedo.xeserv.us/pkg/dhall/kubermemes/k8s/package.dhall sha256:e47e95aba6a08f8ca3e38fbabc436566d6558a05a9b4ac149e8e712c8583b8f0

let tag = env:DRONE_COMMIT_SHA as Text ? "latest"

let image = "xena/printerfacts:${tag}"

in  kms.app.make
      kms.app.Config::{
      , name = "printerfacts"
      , appPort = 5000
      , image
      , replicas = 2
      , domain = "printerfacts.cetacean.club"
      , leIssuer = "prod"
      }
