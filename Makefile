TOOLS   := .tools
FLAGS   := .flags
CONFIGS := .configs
WEBAPP  := .webapp

_F_KIND_REGISTRY        := $(FLAGS)/kind_registry
_F_CLUSTER              := $(FLAGS)/cluster
_F_ISTIO                := $(FLAGS)/istio
_F_NAMESPACE            := $(FLAGS)/ns
_F_HALYARD_DAEMON       := $(FLAGS)/halyard_daemon
_F_SPINNAKER            := $(FLAGS)/spinnaker
_F_WEBAPP_DOCKER_IMAGE  := $(FLAGS)/webapp_docker_image
_F_MINIO                := $(FLAGS)/minio
_F_WEBAPP_HELM_INSTALL  := $(FLAGS)/webapp_helm_install
_F_KIND_NETWORK         := $(FLAGS)/kind_network

_KIND       := ${CURDIR}/$(TOOLS)/kind
_KUBECTL    := ${CURDIR}/$(TOOLS)/kubectl
_HELM       := ${CURDIR}/$(TOOLS)/helm
_ISTIOCTL   := ${CURDIR}/$(TOOLS)/istio/bin/istioctl
_HALYARD    := ${CURDIR}/$(TOOLS)/hal

KUBECONFIG := $(CONFIGS)/kubeconfig

KIND     := KUBECONFIG=$(KUBECONFIG) $(_KIND)
KUBECTL  := KUBECONFIG=$(KUBECONFIG) $(_KUBECTL)
HELM     := KUBECONFIG=$(KUBECONFIG) $(_HELM)
ISTIOCTL := KUBECONFIG=$(KUBECONFIG) $(_ISTIOCTL)
HALYARD  := $(_HALYARD)

WEBAPP_CODE       := $(WEBAPP)/app.py
WEBAPP_DOCKERFILE := $(WEBAPP)/Dockerfile


MINIO_ENDPOINT := $(CONFIGS)/minio_endpoint

################################################################################
# !!! DO NOT EDIT ABOVE THIS LINE !!!
################################################################################

################################################################################
# CONFIGURATION
################################################################################

NS            := apps
ISTIO_PROFILE := demo

MINIO_SECRET_KEY := Pashru@nowjag5
MINIO_ACCESS_KEY := goc.QuiocIsUk7


KIND_DOWNLOAD_URL       := https://kind.sigs.k8s.io/dl/v0.9.0/kind-linux-amd64
KUBECTL_DOWNLOAD_URL    := https://amazon-eks.s3.us-west-2.amazonaws.com/1.17.9/2020-08-04/bin/linux/amd64/kubectl
HELM_DOWNLOAD_URL       := https://get.helm.sh/helm-v3.3.4-linux-amd64.tar.gz
ISTIO_DOWNLOAD_URL      := https://github.com/istio/istio/releases/download/1.7.2/istio-1.7.2-linux-amd64.tar.gz

SPINNAKER_VERSION       := 1.22.1

################################################################################

$(shell mkdir -p $(TOOLS))
$(shell mkdir -p $(FLAGS))
$(shell mkdir -p $(CONFIGS))
$(shell mkdir -p $(WEBAPP))

default: .env $(_KIND) $(_KUBECTL) $(_HELM) $(_ISTIOCTL) \
  $(_F_CLUSTER) $(_F_KIND_NETWORK) $(_F_NAMESPACE) $(_F_ISTIO) $(_F_SPINNAKER) \
  $(_F_WEBAPP_HELM_INSTALL) .env
	@echo "-- Ready."

clean:
	rm -rf $(FLAGS)
	docker stop halyard
	docker stop kind-registry
	$(KIND) delete cluster
	rm -rf $(CONFIGS)
	rm -f .env

.env:
	@echo "export KUBECONFIG=$(KUBECONFIG)" > $@
	@echo "export PATH=${CURDIR}/$(TOOLS):$$PATH" >> $@

$(_KIND):
	curl -Lo $@ "$(KIND_DOWNLOAD_URL)" > /dev/null
	chmod +x $@

$(_KUBECTL):
	curl -Lo $@ "$(KUBECTL_DOWNLOAD_URL)" > /dev/null
	chmod +x $@

$(_HELM): $(_HELM).tar.gz
	tar xzf $@.tar.gz  -C $(@D) linux-amd64/helm
	mv $(@D)/linux-amd64/helm $@
	rm -rf $(@D)/linux-amd64
	touch $@
	chmod +x $@

$(_HELM).tar.gz:
	curl -Lo $@ "$(HELM_DOWNLOAD_URL)" > /dev/null

$(TOOLS)/istio.tar.gz:
	curl -Lo $@ "$(ISTIO_DOWNLOAD_URL)" > /dev/null

$(_ISTIOCTL): $(TOOLS)/istio.tar.gz
	tar xzf $(TOOLS)/istio.tar.gz -C $(TOOLS)
	rm -rf $(TOOLS)/istio
	mv $(TOOLS)/istio-* $(TOOLS)/istio/
	ln -sf ${CURDIR}/$(TOOLS)/istio/bin/istioctl ${CURDIR}/$(TOOLS)/istioctl
	touch $@
	chmod +x $@

$(_HALYARD): $(_F_HALYARD_DAEMON)
	sed -n 's/^#hal://p' < Makefile > $@
	chmod +x $@

$(_F_KIND_REGISTRY):
	docker run \
	    -d --rm -p "5000:5000" --name kind-registry \
	    registry:2 \
	&& touch $@

$(CONFIGS)/cluster.yaml:
	sed -n 's/^#kind_cluster://p' < Makefile > $@

$(_F_CLUSTER): $(_F_KIND_REGISTRY) $(CONFIGS)/cluster.yaml
	$(KIND) create cluster --config $(CONFIGS)/cluster.yaml \
	&& for node in `$(KIND) get nodes`; do \
	  $(KUBECTL) annotate node "$${node}" "kind.x-k8s.io/registry=localhost:5000"; \
	done \
	&& touch $@

$(_F_KIND_NETWORK):
	docker network connect "kind" "kind-registry" \
	&& touch $@

$(_F_HALYARD_DAEMON):
	mkdir -p $(CONFIGS)/.hal
	docker run -p 8084:8084 -p 9000:9000 \
	  --name halyard --rm \
	  --net=host \
	  -v ${CURDIR}/$(CONFIGS)/.hal:/home/spinnaker/.hal \
	  -v ${CURDIR}/$(KUBECONFIG):/home/spinnaker/.kube/config \
	  -d \
	  gcr.io/spinnaker-marketplace/halyard:stable \
	&& touch $@ \
	&& sleep 15

$(_F_MINIO):
	$(KUBECTL) create namespace minio
	$(HELM) repo add minio https://helm.min.io/
	$(HELM) install --namespace minio \
	  --set accessKey=$(MINIO_ACCESS_KEY),secretKey=$(MINIO_SECRET_KEY),persistence.enabled=false \
	  --generate-name minio/minio \
	&& touch $@

$(MINIO_ENDPOINT):
	SVC_NAME=`$(KUBECTL) get svc -n minio --output=jsonpath={.items..metadata.name}` ; \
	echo "$${SVC_NAME}.minio.svc.cluster.local" > $@

$(_F_SPINNAKER): $(_F_MINIO) $(MINIO_ENDPOINT) $(_HALYARD)
	$(HALYARD) config provider kubernetes enable
	CONTEXT=`$(KUBECTL) config current-context`; \
	  $(HALYARD) config provider kubernetes account add k8s-toy --context $$CONTEXT
	$(HALYARD) config deploy edit --type distributed --account-name k8s-toy
	$(HALYARD) config version edit --version $(SPINNAKER_VERSION)
	$(HALYARD) config storage s3 edit --endpoint http://`cat $(MINIO_ENDPOINT)` \
	  --access-key-id $(MINIO_ACCESS_KEY) \
	  --secret-access-key $(MINIO_SECRET_KEY)
	$(HALYARD) config storage s3 edit --path-style-access true
	$(HALYARD) config storage edit --type s3
	$(HALYARD) config stats disable
	sleep 5
	$(HALYARD) deploy apply --no-validate \
	&& touch $@

$(_F_NAMESPACE):
	$(KUBECTL) create namespace $(NS) \
	&& touch $@

$(_F_ISTIO):
	$(ISTIOCTL) install --set profile=$(ISTIO_PROFILE) \
	&& touch $@

$(WEBAPP_CODE):
	sed -n 's/^#app.py://p' < Makefile > $@

$(WEBAPP_DOCKERFILE):
	sed -n 's/^#webapp_dockerfile://p' < Makefile > $@

$(_F_WEBAPP_DOCKER_IMAGE): $(WEBAPP_DOCKERFILE) $(WEBAPP_CODE)
	docker build -t webapp -f $(WEBAPP)/Dockerfile $(WEBAPP)
	docker tag webapp localhost:5000/webapp:0.1.0
	docker push localhost:5000/webapp:0.1.0 \
	&& touch $@

$(CONFIGS)/webapp-0.1.0.tgz: $(_F_WEBAPP_DOCKER_IMAGE)
	cd $(CONFIGS) && $(HELM) create webapp
	sed -n 's/^#webapp_chart://p' < Makefile > $(CONFIGS)/webapp/Chart.yaml
	sed -n 's/^#webapp_values://p' < Makefile > $(CONFIGS)/webapp/values.yaml
	cd $(CONFIGS)/webapp && $(HELM) lint
	cd $(CONFIGS) && $(HELM) package webapp

$(_F_WEBAPP_HELM_INSTALL): $(CONFIGS)/webapp-0.1.0.tgz
	$(HELM) install --generate-name \
	  --namespace $(NS) $< \
	&& touch $@

.PHONY: default clean

#kind_cluster:kind: Cluster
#kind_cluster:apiVersion: kind.x-k8s.io/v1alpha4
#kind_cluster:containerdConfigPatches:
#kind_cluster:- |-
#kind_cluster:  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
#kind_cluster:    endpoint = ["http://kind-registry:5000"]

#hal:#!/bin/sh
#hal:docker exec halyard hal $@

#app.py:from fastapi import FastAPI
#app.py:
#app.py:app = FastAPI()
#app.py:
#app.py:@app.get("/hello")
#app.py:async def hello():
#app.py:    return {"message": "hello, world"}
#app.py:
#app.py:@app.get("/")
#app.py:async def health_check():
#app.py:    return {"status": "RUNNING"}

#webapp_dockerfile:FROM python:3.8-buster
#webapp_dockerfile:RUN pip install fastapi uvicorn
#webapp_dockerfile:COPY app.py /app/app.py
#webapp_dockerfile:WORKDIR /app
#webapp_dockerfile:CMD [ "uvicorn", \
#webapp_dockerfile:      "app:app", \
#webapp_dockerfile:      "--host", "0.0.0.0" ]

#webapp_chart:apiVersion: v2
#webapp_chart:name: webapp
#webapp_chart:description: A Helm chart for Kubernetes
#webapp_chart:type: application
#webapp_chart:version: 0.1.0
#webapp_chart:appVersion: 0.1.0

#webapp_values:replicaCount: 1
#webapp_values:
#webapp_values:image:
#webapp_values:  repository: localhost:5000/webapp
#webapp_values:  pullPolicy: IfNotPresent
#webapp_values:  # Overrides the image tag whose default is the chart appVersion.
#webapp_values:  tag: ""
#webapp_values:
#webapp_values:imagePullSecrets: []
#webapp_values:nameOverride: ""
#webapp_values:fullnameOverride: ""
#webapp_values:
#webapp_values:serviceAccount:
#webapp_values:  # Specifies whether a service account should be created
#webapp_values:  create: true
#webapp_values:  # Annotations to add to the service account
#webapp_values:  annotations: {}
#webapp_values:  # The name of the service account to use.
#webapp_values:  # If not set and create is true, a name is generated using the fullname template
#webapp_values:  name: ""
#webapp_values:
#webapp_values:podAnnotations: {}
#webapp_values:
#webapp_values:podSecurityContext: {}
#webapp_values:  # fsGroup: 2000
#webapp_values:
#webapp_values:securityContext: {}
#webapp_values:  # capabilities:
#webapp_values:  #   drop:
#webapp_values:  #   - ALL
#webapp_values:  # readOnlyRootFilesystem: true
#webapp_values:  # runAsNonRoot: true
#webapp_values:  # runAsUser: 1000
#webapp_values:
#webapp_values:service:
#webapp_values:  type: ClusterIP
#webapp_values:  port: 8000
#webapp_values:
#webapp_values:ingress:
#webapp_values:  enabled: false
#webapp_values:  annotations: {}
#webapp_values:    # kubernetes.io/ingress.class: nginx
#webapp_values:    # kubernetes.io/tls-acme: "true"
#webapp_values:  hosts:
#webapp_values:    - host: chart-example.local
#webapp_values:      paths: []
#webapp_values:  tls: []
#webapp_values:  #  - secretName: chart-example-tls
#webapp_values:  #    hosts:
#webapp_values:  #      - chart-example.local
#webapp_values:
#webapp_values:resources: {}
#webapp_values:  # We usually recommend not to specify default resources and to leave this as a conscious
#webapp_values:  # choice for the user. This also increases chances charts run on environments with little
#webapp_values:  # resources, such as Minikube. If you do want to specify resources, uncomment the following
#webapp_values:  # lines, adjust them as necessary, and remove the curly braces after 'resources:'.
#webapp_values:  # limits:
#webapp_values:  #   cpu: 100m
#webapp_values:  #   memory: 128Mi
#webapp_values:  # requests:
#webapp_values:  #   cpu: 100m
#webapp_values:  #   memory: 128Mi
#webapp_values:
#webapp_values:autoscaling:
#webapp_values:  enabled: false
#webapp_values:  minReplicas: 1
#webapp_values:  maxReplicas: 100
#webapp_values:  targetCPUUtilizationPercentage: 80
#webapp_values:  # targetMemoryUtilizationPercentage: 80
#webapp_values:
#webapp_values:nodeSelector: {}
#webapp_values:
#webapp_values:tolerations: []
#webapp_values:
#webapp_values:affinity: {}
