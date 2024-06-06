# Contribute to the NVIDIA NIM Deploy Project

## Introduction
NVIDIA NIMs provide a simplified way to deploy optimized AI applications into production that support a [large list](https://ai.nvidia.com) of AI models.

Existing NVIDIA components such as NVIDIA drivers, the [NVIDIA Container Toolkit](https://github.com/NVIDIA/nvidia-container-toolkit), the [NVIDIA CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit), or the [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator) exist and are installed on the host or into a Kubernetes cluster to enable AI applications. NVIDIA NIMs run on top of this GPU-enabled platform to deliver AI applications that developers can embed directly into their programs using API calls.


## Architecture
The NIM Deploy Project is made up components that outline various deployment scenarios (KServe, Helm, Operator, CSP, ISV, etc.), along with guides that are meant as example material to show end to end workflows for deployment and demo usage, there maybe be references to several related NVIDIA projects including:

The NIM Deploy Project leverages the following software components, but they are not included as part of the NIM Deploy project. The associated code is linked to each of the components below:

* [Cloud Native Stack](https://github.com/NVIDIA/cloud-native-stack)
* [Generative AI Examples](https://github.com/NVIDIA/GenerativeAIExamples)
* [NVIDIA API Catalog](https://build.nvidia.com/)


## License
The NVIDIA NIM Deploy Project is open-source and its components are licensed under the permissive Apache 2.0 license.

## Artifacts
The NVIDIA NIM Deploy has four artifacts as part of the project release:
1. Guides
2. KServe YAML
3. Helm Charts
4. Operator Source Code

There is currently no defined release flow, as this project is meant for experimental design and integrations.

## Contributions
NVIDIA is willing to work with partners for adding platform support for NVIDIA NIM. The NVIDIA NIM Deploy Project is open-source and permissively licensed under the Apache 2.0 license with only minimal requirements for source code [contributions](#signing).

Please work with the NVIDIA team through GitHub issues to determine appropriate testing and CI for new platform support.

## <a name="signing"></a>Signing your work

Want to hack on the NVIDIA NIM Deploy Project? Awesome!

We require that all contributions are certified under the terms of the Developer Certificate of Origin (DCO), Version 1.1.

This certifies that the contribution is your original work or you have the right to submit it under the same or compatible license. Any public contribution that contains commits that are not signed off will not be accepted.

To simplify the process, we accept GPG-signed commits as fulfilling the requirements of the DCO.

### Why GPG Signatures?

A GPG-signed commit provides cryptographic assurance that the commit was made by the holder of the corresponding private key. By configuring your commits to be signed by GPG, you not only enhance the security of the repository but also implicitly certify that you have the rights to submit the work under the project's license and agree to the DCO terms.

### Setting Up Git for Signed Commits

1. **Generate a GPG key pair**:

    If you don't already have a GPG key, you can generate a new GPG key pair by following the instructions here: [Generating a new GPG key](https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key).

2. **Add your GPG key to your GitHub/GitLab account**:

   After generating your GPG key, add it to your GitHub account by following these steps: [Adding a new GPG key to your GitHub account](https://docs.github.com/en/authentication/managing-commit-signature-verification/adding-a-gpg-key-to-your-github-account).

3. **Configure Git to sign commits:**

   Tell Git to use your GPG key by default for signing your commits:
   ```bash
   git config --global user.signingkey YOUR_GPG_KEY_ID
   ```
4. **Sign commits**:

   Sign individual commits using the `-S` flag
   ```bash
   git commit -S -m "Your commit message"
   ```
   Or, enable commit signing by default (recommended):
   ```bash
   git config --global commit.gpgsign true
   ```

**Troubleshooting and Help**: If you encounter any issues or need help with setting up commit signing, please refer to the [GitHub documentation on signing commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits).
Feel free to contact the project maintainers if you need further assistance.

### Developer Certificate of Origin (DCO)

To ensure the quality and legality of the code base, all contributors are required to certify the origin of their contributions under the terms of the Developer Certificate of Origin (DCO), Version 1.1:

  ```
  Developer Certificate of Origin
  Version 1.1

  Copyright (C) 2004, 2006 The Linux Foundation and its contributors.
  1 Letterman Drive
  Suite D4700
  San Francisco, CA, 94129

  Everyone is permitted to copy and distribute verbatim copies of this license document, but changing it is not allowed.

  Developer's Certificate of Origin 1.1

  By making a contribution to this project, I certify that:

  (a) The contribution was created in whole or in part by me and I have the right to submit it under the open source license indicated in the file; or

  (b) The contribution is based upon previous work that, to the best of my knowledge, is covered under an appropriate open source license and I have the right under that license to submit that work with modifications, whether created in whole or in part by me, under the same open source license (unless I am permitted to submit under a different license), as indicated in the file; or

  (c) The contribution was provided directly to me by some other person who certified (a), (b) or (c) and I have not modified it.

  (d) I understand and agree that this project and the contribution are public and that a record of the contribution (including all personal information I submit with it, including my sign-off) is maintained indefinitely and may be redistributed consistent with this project or the open source license(s) involved.
  ```

We look forward to your contributions to the NVIDIA NIM Deploy Project!
