# k8s-toy-setup

by Yaroslav Tarasenko (consulting@devdataops.de)

What is this?
-------------

k8s-toy-setup helps you get familiar with modern kubernetes tooling in the comfort of your laptop.

Features
--------

- installation of binaries only happens in the directory with this README
- modern k8s tools are presented
  - kind for a local kubernetes
  - istio & spinnaker installed
  - minio as a persistence storage for spinnaker
  - example dockerfile for a python web application + a helm chart

Requirements
------------

Before working with k8s-toy-setup make sure you have the following software installed:

- docker
- tar
- curl
- sed
- make

The only supported OS is Linux.

How to use
----------

Clone this repository. In your terminal application, cd to the repository's directory and type

```bash
make
```

This will bring up a local kubernetes cluster with a service mesh &
spinnaker installed in it and an example web application deployed with
helm.

Once make finishes, you can start working with the freshly installed local cluster using kubectl, helm and friends:

```bash
. .env  # set the needed environment variables
kubectl get nodes
kubectl get pod -n apps
```

Please note that pulling docker images onto cluster nodes will take
some additional time (~ 10 mins on my machine), so spinnaker and the
example app will not be available until you see 'Running' in pod
listings.

To play with the example webapp, wait until the pod is running and issue these commands:

```bash
export POD_NAME=$(kubectl get pods --namespace apps -l "app.kubernetes.io/name=webapp" -o jsonpath="{.items[0].metadata.name}")
kubectl --namespace apps port-forward $POD_NAME 8080:80
```

In another terminal session you can try to query the example webapp:

```bash
curl localhost
curl localhost/hello
```

To access spinnaker UI type in your terminal session:

```bash
hal deploy connect
```

and navigate to `localhost:9000` in your browser.


### Uninstall

To remove the toy cluster along with its configuration and any related state, type

```bash
make clean
```

Configuration
-------------

Open `Makefile` in your editor of choice and search for a banner
`CONFIGURATION`. Change values of variables you are interested in and
rerun make:

```bash
make clean
make
```

Known Issues
------------

- front50 pod from spinnaker fails to connect to minio

Next Steps
----------

- canary deployment setup of the example app using spinnaker

Contributing
------------

Pull/merge requests are welcome. For major changes, please open an issue first to discuss what you would like to change.


License
-------

[MIT](https://spdx.org/licenses/MIT.html)
