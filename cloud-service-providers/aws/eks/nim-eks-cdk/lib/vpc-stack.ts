import * as cdk from "aws-cdk-lib";
import { IpAddresses, SubnetType, Vpc } from "aws-cdk-lib/aws-ec2";
import { Construct } from "constructs";
export class VpcStack extends cdk.Stack {
  readonly vpc: Vpc;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);
    this.vpc = new Vpc(this, "nim-eks-vpc", {
      vpcName: "nim-eks-vpc",
      ipAddresses: IpAddresses.cidr("10.0.0.0/16"),
      maxAzs: 2,
      natGateways: 1,
      subnetConfiguration: [
        {
          name: "PrivateSubnet",
          subnetType: SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          name: "PublicSubnet",
          subnetType: SubnetType.PUBLIC,
        },
      ],
    });
  }
}
