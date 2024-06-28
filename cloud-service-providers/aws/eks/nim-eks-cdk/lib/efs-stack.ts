//@tslint
import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import {
  aws_ec2 as ec2,
  aws_iam as iam,
  aws_efs as efs,
  aws_eks as eks,
} from "aws-cdk-lib";
import { Peer, Port, Vpc } from "aws-cdk-lib/aws-ec2";
import { Cluster } from "aws-cdk-lib/aws-eks";

interface EfsStackProps extends cdk.StackProps {
  vpc: Vpc;
  cluster: Cluster;
}
export class EfsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: EfsStackProps) {
    super(scope, id, props);

    // Create a new security group
    const efs_securityGroup = new ec2.SecurityGroup(
      this,
      "efs-security-group",
      {
        vpc: props.vpc,
        allowAllOutbound: true,
        securityGroupName: "efs-security-group",
      }
    );

    // Add an inbound rule to allow connections on port 2049
    efs_securityGroup.addIngressRule(
      Peer.ipv4(props.vpc.vpcCidrBlock),
      Port.tcp(2049),
      "Allow NFS Connections"
    );

    // Create a new Amazon EFS file system
    const fileSystem = new efs.FileSystem(this, "nim-efs", {
      vpc: props.vpc,
      securityGroup: efs_securityGroup,
      allowAnonymousAccess: true,
    });

    const efsDriverPolicyStatement = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        "elasticfilesystem:DescribeAccessPoints",
        "elasticfilesystem:DescribeFileSystems",
        "elasticfilesystem:DescribeMountTargets",
        "elasticfilesystem:CreateAccessPoint",
        "elasticfilesystem:TagResource",
        "elasticfilesystem:DeleteAccessPoint",
        "ec2:DescribeAvailabilityZones",
      ],
      resources: ["*"],
    });

    const efs_csi_driver_role = new iam.Role(
      this,
      "AmazonEKS_EFS_CSI_DriverRole",
      {
        roleName: "AmazonEKS_EFS_CSI_DriverRole",
        assumedBy: new iam.FederatedPrincipal(
          props.cluster.openIdConnectProvider.openIdConnectProviderArn,
          {},
          "sts:AssumeRoleWithWebIdentity"
        ),
      }
    );

    efs_csi_driver_role.addToPolicy(efsDriverPolicyStatement);

    new eks.CfnAddon(this, "MyCfnAddon", {
      addonName: "aws-efs-csi-driver",
      clusterName: props.cluster.clusterName,
      serviceAccountRoleArn: efs_csi_driver_role.roleArn,
    });

    new cdk.CfnOutput(this, "FileSystemIdOutput", {
      value: fileSystem.fileSystemId,
    });
  }
}
