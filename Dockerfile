FROM univa/awscli

ADD CentOS-7-GenericCloud-to-AMI.sh  /CentOS-7-GenericCloud-to-AMI.sh
CMD /CentOS-7-GenericCloud-to-AMI.sh
