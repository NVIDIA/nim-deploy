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
We only require that developers sign their work, the below section describes this!

The sign-off is a simple line at the end of the explanation for the patch. Your
signature certifies that you wrote the patch or otherwise have the right to pass
it on as an open-source patch. The rules are pretty simple: if you can certify
the below (from [developercertificate.org](http://developercertificate.org/)):

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.
1 Letterman Drive
Suite D4700
San Francisco, CA, 94129

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

Then you just add a line to every git commit message:

    Signed-off-by: Joe Smith <joe.smith@email.com>

Use your real name (sorry, no pseudonyms or anonymous contributions.)

If you set your `user.name` and `user.email` git configs, you can sign your
commit automatically with `git commit -s`.
