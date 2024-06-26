import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import { aws_eks as eks, aws_ec2 as ec2, aws_iam as iam } from "aws-cdk-lib";
import { AlbControllerVersion, Cluster } from "aws-cdk-lib/aws-eks";
import { Vpc } from "aws-cdk-lib/aws-ec2/lib/vpc";
import { KubectlV29Layer } from "@aws-cdk/lambda-layer-kubectl-v29";
import { Peer, Port } from "aws-cdk-lib/aws-ec2";

interface EksClusterStackProps extends cdk.StackProps {
  vpc: Vpc;
}

export class EksClusterStack extends cdk.Stack {
  readonly cluster: Cluster;
  constructor(scope: Construct, id: string, props: EksClusterStackProps) {
    super(scope, id, props);

    // Define IAM policy statement to allow list access to eks cluster
    const eksPolicyStatement = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ["eks:*"],
      resources: ["*"],
    });

    // Define IAM policy statement to describe cloudformatiom stacks
    const cfnPolicyStatement = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ["cloudformation:DescribeStacks"],
      resources: ["*"],
    });

    // Create the EKS cluster
    this.cluster = new eks.Cluster(this, "nim-eks-cluster", {
      defaultCapacity: 0,
      vpc: props.vpc,
      version: eks.KubernetesVersion.V1_29,
      kubectlLayer: new KubectlV29Layer(this, "kubectl"),
      ipFamily: eks.IpFamily.IP_V4,
      outputClusterName: true,
      outputConfigCommand: true,
      endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
      albController: {
        version: AlbControllerVersion.V2_6_2,
      },
    });

    // Attach policy statement to the user
    const adminUser = new iam.User(this, "Admin");
    adminUser.addToPolicy(eksPolicyStatement);
    adminUser.addToPolicy(cfnPolicyStatement);
    this.cluster.awsAuth.addUserMapping(adminUser, {
      groups: ["system:masters"],
    });

    // Create a new security group
    const eks_node_securityGroup = new ec2.SecurityGroup(
      this,
      "eks-node-security-group",
      {
        vpc: props.vpc,
        allowAllOutbound: true,
        securityGroupName: "eks-node-security-group",
      }
    );

    // Add an inbound rule to allow connections on port 2049
    eks_node_securityGroup.addIngressRule(
      Peer.ipv4(props.vpc.vpcCidrBlock),
      Port.allTraffic(),
      "Allow NFS Connections"
    );

    this.cluster.addNodegroupCapacity("nim-node-group", {
      instanceTypes: [new ec2.InstanceType("g5.12xlarge")],
      minSize: 1,
      diskSize: 100,
      amiType: eks.NodegroupAmiType.AL2_X86_64_GPU,
      nodeRole: new iam.Role(this, "eksClusterNodeGroupRole", {
        roleName: "eksClusterNodeGroupRole",
        assumedBy: new iam.ServicePrincipal("ec2.amazonaws.com"),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName(
            "AmazonEKSWorkerNodePolicy"
          ),
          iam.ManagedPolicy.fromAwsManagedPolicyName(
            "AmazonEC2ContainerRegistryReadOnly"
          ),
          iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonEKS_CNI_Policy"),
          iam.ManagedPolicy.fromAwsManagedPolicyName(
            "AmazonSSMManagedInstanceCore"
          ),
          iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonS3ReadOnlyAccess"),
        ],
      }),
    });

    this.cluster.clusterSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.allTraffic()
    );

    const ebsDriverPolicyStatement = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        "ec2:CreateSnapshot",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:ModifyVolume",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInstances",
        "ec2:DescribeSnapshots",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumesModifications",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "kms:CreateKey",
        "kms:CreateGrant",
        "kms:DescribeKey",
        "kms:ListKeys",
        "kms:GetKeyPolicy",
        "kms:ListResourceTags",
        "kms:TagResource",
        "kms:UntagResource",
      ],
      resources: ["*"],
    });

    const ebs_csi_driver_role = new iam.Role(
      this,
      "AmazonEKS_EBS_CSI_DriverRole",
      {
        roleName: "AmazonEKS_EBS_CSI_DriverRole",
        assumedBy: new iam.FederatedPrincipal(
          this.cluster.openIdConnectProvider.openIdConnectProviderArn,
          {},
          "sts:AssumeRoleWithWebIdentity"
        ),
      }
    );

    ebs_csi_driver_role.addToPolicy(ebsDriverPolicyStatement);

    new eks.CfnAddon(this, "MyCfnAddon", {
      addonName: "aws-ebs-csi-driver",
      clusterName: this.cluster.clusterName,
      serviceAccountRoleArn: ebs_csi_driver_role.roleArn,
    });
  }
}
