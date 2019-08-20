#!/bin/sh -x

yum install -y aws-cli
eval $(aws ecr get-login --region us-east-1 --no-include-email)
cp -R /root/.docker /home/ec2-user/
chown -R ec2-user:ec2-user /home/ec2-user/.docker
