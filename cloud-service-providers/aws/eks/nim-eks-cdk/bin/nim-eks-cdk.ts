#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { EfsStack } from '../lib/efs-stack';
import { EksClusterStack } from '../lib/eks-cluster-stack';
import { VpcStack } from '../lib/vpc-stack';

const app = new cdk.App();

const vpcStack = new VpcStack(app, 'vpc-stack');

const eksClusterStack = new EksClusterStack(app, 'eks-cluster-stack', {
    vpc: vpcStack.vpc
});
const efsStack = new EfsStack(app,'efs-stack', {
  vpc: vpcStack.vpc,
  cluster: eksClusterStack.cluster
})