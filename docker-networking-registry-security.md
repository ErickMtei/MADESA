# Docker wa Kina: Networking, Registry, na Container Security
### Somo kamili kwa Kiswahili — na mifano halisi

> Lengo la somo hili ni ujue Docker **kabisa**, si kuelewa juu juu tu. Kila mada ina: (1) maelezo ya kina ya *kwa nini* na *jinsi gani* inavyofanya kazi ndani, (2) amri halisi za kujaribu, (3) matokeo yanayotegemewa, na (4) matumizi ya kiuhalisia (real-world use case).

---

# SEHEMU YA 1: DOCKER NETWORKING

Kabla ya kuingia kwenye aina za networks, lazima uelewe dhana ya msingi:

Kila container inapoanzishwa, Docker huunda **network namespace** tofauti (kutoka Linux kernel) kwa ajili yake. Hii ina maana container ina interface zake za mtandao (`eth0`), routing table yake, na `iptables` rules zake — tofauti kabisa na host machine. Docker daemon (`dockerd`) ndiye anayeunganisha (connect) namespaces hizi kwa kila mmoja kwa kutumia **network drivers**.

Amri ya msingi ya kuona networks zilizopo kwenye mfumo wako:

```bash
docker network ls
```

Utaona kitu kama:

```
NETWORK ID     NAME      DRIVER    SCOPE
8f3a2b1c9d4e   bridge    bridge    local
1a2b3c4d5e6f   host      host      local
9f8e7d6c5b4a   none      null      local
```

Hizi tatu (`bridge`, `host`, `none`) zinakuja **default** kila unapofunga Docker. Sasa tuzichambue moja baada ya nyingine.

---

## 1.1 Bridge Network (default)

### Nadharia
Bridge ni network driver ya default kwa containers zote unazounda bila kuainisha `--network`. Docker huunda **virtual switch** (inaitwa `docker0` kwenye host — angalia kwa `ip addr show docker0`) ambayo containers zote zinazounganishwa nayo zinaweza kuongea moja na nyingine kupitia IP addresses za ndani (private, kama `172.17.0.0/16`).

Docker hutumia **NAT (Network Address Translation)** kupitia `iptables` kuruhusu containers kufikia internet (outbound), lakini kwa default, dunia ya nje HAIWEZI kufikia container (inbound) — lazima u-*publish* port kwa mkono.

### Mfano halisi

```bash
# Tengeneza custom bridge network (bora kuliko default bridge kwa sababu inatoa DNS resolution kati ya containers)
docker network create --driver bridge my-app-net

# Angalia details za network - subnet, gateway, n.k
docker network inspect my-app-net
```

Matokeo (sehemu muhimu):

```json
"IPAM": {
    "Config": [
        {
            "Subnet": "172.18.0.0/16",
            "Gateway": "172.18.0.1"
        }
    ]
}
```

Sasa tuunde containers mbili kwenye network hii moja:

```bash
docker run -d --name db --network my-app-net postgres:16
docker run -d --name api --network my-app-net -e DB_HOST=db nginx:alpine
```

**Jambo la muhimu sana**: kwenye *custom* bridge network (si default `bridge`), Docker inatoa **automatic DNS resolution**. Container `api` inaweza ku-*ping* au ku-*connect* kwa jina `db` moja kwa moja:

```bash
docker exec -it api ping db
# PING db (172.18.0.2): itafanya kazi!
```

Kwenye **default bridge** (`docker0`), hii haifanyi kazi — lazima utumie `--link` (deprecated) au IP address moja kwa moja. Hii ndiyo sababu documentation zote za Docker zinashauri: **usitumie default bridge kwa production**, tengeneza custom bridge kila wakati.

### Real-world use case
App ya kawaida yenye web server + database kwenye seva moja (single host) — hii ndiyo inayotumika sana kwenye `docker-compose.yml`, kwa sababu Compose inaunda custom bridge network moja kwa moja kwa services zote.

```yaml
# docker-compose.yml
services:
  api:
    image: nginx:alpine
    networks:
      - backend
  db:
    image: postgres:16
    networks:
      - backend
networks:
  backend:
    driver: bridge
```

---

## 1.2 Host Network

### Nadharia
Container ikitumia `--network host`, Docker **HAITENGENEZI** network namespace mpya kabisa. Container inatumia network stack ya host moja kwa moja — hakuna NAT, hakuna port mapping, hakuna isolation ya mtandao. Ukisikiliza port 8080 ndani ya container, ni sawa na kusikiliza port 8080 kwenye host yenyewe.

### Mfano halisi

```bash
docker run -d --network host nginx:alpine
```

Sasa nginx inasikiliza moja kwa moja kwenye `localhost:80` ya host yako — hutahitaji `-p 80:80` kabisa (ukijaribu kutumia `-p` na `--network host` pamoja, Docker itaipuuza kimya kimya na kutoa warning).

Jaribu:
```bash
curl http://localhost:80
```
Itafanya kazi bila `-p` yoyote.

### Faida na hasara
* **Faida**: Performance ya juu zaidi (hakuna overhead ya NAT/bridge translation), inafaa kwa high-throughput apps (kama load balancers, monitoring agents).
* **Hasara kubwa**: **Hakuna network isolation**. Container inaweza kuona/kutumia ports zote za host, na kinyume chake. Hii ni hatari ya kiusalama — usitumie kwa apps zisizoaminika.

### Real-world use case
Monitoring agents kama `node_exporter` (Prometheus) mara nyingi hutumia host network ili kuona metrics halisi za mtandao wa host bila translation ya NAT kuharibu takwimu.

---

## 1.3 None Network

### Nadharia
Container haina interface ya mtandao kabisa (isipokuwa `lo` - loopback ya ndani yake). Haiwezi kuongea na chochote nje, wala na containers nyingine.

### Mfano halisi

```bash
docker run -it --network none alpine sh
```

Ndani ya shell hiyo:
```bash
ip addr
# Utaona tu: lo (loopback) - hakuna eth0
ping google.com
# Itashindwa - "Network unreachable"
```

### Real-world use case
* Kazi za batch processing zisizohitaji mtandao kabisa (mfano: kuchakata faili za ndani, compute-only jobs) — kuondoa uwezo wa mtandao ni **security hardening** (hata kama malicious code ikijificha ndani, haiwezi ku-*exfiltrate* data).
* CI/CD sandboxes zinazojaribu code isiyoaminika.

---

## 1.4 Overlay Network

### Nadharia
Overlay ni tofauti kabisa — inatumika **Docker Swarm** (au Kubernetes-style multi-host clustering) kuunganisha containers zinazoendesha kwenye **hosts (nodes) tofauti** kana kwamba ziko kwenye network moja. Inatumia teknolojia ya **VXLAN** kufunika (encapsulate) packets za Layer 2 ndani ya Layer 3 UDP packets, ili zisafiri kupitia physical network ya kawaida (hata internet) kati ya servers tofauti.

### Mfano halisi (Docker Swarm)

Kwanza anzisha Swarm kwenye node ya kwanza (manager):

```bash
docker swarm init --advertise-addr <IP-YA-MANAGER>
```

Hii itatoa amri ya `docker swarm join` yenye token — nakili na endesha kwenye node nyingine (worker):

```bash
docker swarm join --token SWMTKN-xxxx <IP-YA-MANAGER>:2377
```

Sasa tengeneza overlay network kwenye manager:

```bash
docker network create --driver overlay --attachable my-overlay
```

`--attachable` inaruhusu standalone containers (si tu services) kujiunga.

Tengeneza service inayotumia overlay hii, itasambazwa (replicated) kwenye nodes zote:

```bash
docker service create --name web --network my-overlay --replicas 3 nginx:alpine
```

Angalia containers zilizosambaa kwenye nodes tofauti:

```bash
docker service ps web
```

Containers hizi tatu, hata kama ziko kwenye physical servers tofauti kabisa, zinaweza kuongeana kwa DNS name (`web`) kupitia overlay network — VXLAN inashughulikia usafirishaji wa packets kati ya hosts kwa uwazi (transparently).

### Real-world use case
Microservices architecture inayoendesha kwenye cluster ya servers kadhaa (mfano: e-commerce app yenye `orders-service` node 1, `payments-service` node 2, `inventory-service` node 3) — overlay network inawawezesha kuongea kana kwamba wako local, wakati kiuhalisia wametawanyika duniani kote.

---

## 1.5 Macvlan Network

### Nadharia
Macvlan inampa container **MAC address yake halisi** na kuifanya ionekane kwenye physical network kama **kifaa halisi cha mtandao (physical device)** - siyo behind NAT tena. Container inapata IP address moja kwa moja kutoka kwa router/DHCP ya network yako ya kawaida (physical LAN), sio kutoka kwa Docker's internal subnet.

### Mfano halisi

```bash
docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  -o parent=eth0 \
  my-macvlan-net
```

`parent=eth0` inaonyesha physical interface ya host inayotumika kuunganisha macvlan hii kwenye physical network yako.

```bash
docker run -d --name legacy-app --network my-macvlan-net \
  --ip=192.168.1.50 nginx:alpine
```

Sasa container hii ina IP `192.168.1.50` moja kwa moja kwenye LAN yako — vifaa vingine kwenye mtandao (kompyuta, printer, simu) vinaweza ku-*ping* container hii moja kwa moja kama vile ni kompyuta halisi, bila port mapping yoyote.

**Kizuizi muhimu**: Kwa default, host haiwezi kuongea moja kwa moja na macvlan container yake yenyewe (kuna kizuizi cha Linux kernel kuhusu hili) — unahitaji kutengeneza macvlan interface ya ziada kwenye host kama unataka host-to-container communication.

### Real-world use case
Kubadilisha (migrate) legacy applications zinazohitaji IP address yake mwenyewe kwenye network (kama vile appliances za zamani zinazotambuliwa kwa IP maalum na firewall rules, au apps zinazohitaji kuonekana kama "physical box" kwa sababu za compliance/monitoring).

---

## 1.6 IPv4 na IPv6 kwenye Docker

### Nadharia
Kwa default, Docker inatumia **IPv4 pekee**. IPv6 lazima uiwashe (enable) kimakusudi kwenye Docker daemon config.

### Kuwasha IPv6

Hariri (au tengeneza) `/etc/docker/daemon.json`:

```json
{
  "ipv6": true,
  "fixed-cidr-v6": "2001:db8:1::/64"
}
```

Kisha:
```bash
sudo systemctl restart docker
```

Tengeneza network ya dual-stack (IPv4 + IPv6):

```bash
docker network create --ipv6 \
  --subnet=172.20.0.0/16 \
  --subnet=2001:db8:2::/64 \
  dual-stack-net

docker run -d --name web --network dual-stack-net nginx:alpine

docker inspect web | grep -A 5 IPAddress
```

Utaona container ina anwani zote mbili: IPv4 (`172.20.0.x`) na IPv6 (`2001:db8:2::x`).

### Real-world use case
Apps zinazolengwa kutumika duniani kote (globally) ambapo baadhi ya ISPs (hasa mobile carriers) zinatumia IPv6-only networks — bila dual-stack support, watumiaji hao hawawezi kufikia service yako moja kwa moja.

---

## 1.7 DNS ndani ya Docker

### Nadharia
Docker ina built-in DNS server (inaendesha kwenye `127.0.0.11` ndani ya kila container) inayoshughulikia:
1. **Service discovery** kati ya containers kwenye custom network moja (kwa jina la container/service).
2. **External DNS resolution** (mfano `google.com`) kwa ku-*forward* maombi kwenda kwa DNS servers za host (au ulizoainisha).

### Mfano halisi

```bash
docker network create test-net
docker run -d --name server1 --network test-net alpine sleep 3600
docker run -it --name client1 --network test-net alpine sh
```

Ndani ya `client1`:
```bash
cat /etc/resolv.conf
# nameserver 127.0.0.11   <- huu ni Docker's internal DNS

ping server1
# Inafanya kazi kwa sababu Docker DNS inatafsiri "server1" kuwa IP yake
```

Unaweza pia kutumia **DNS alias** (jina la ziada la container):

```bash
docker run -d --name server2 --network test-net \
  --network-alias database alpine sleep 3600
```

Sasa containers nyingine kwenye `test-net` zinaweza kufikia `server2` kwa majina mawili: `server2` NA `database`.

Kubadilisha custom DNS servers (mfano kutumia Google DNS badala ya default):

```bash
docker run -d --dns=8.8.8.8 --dns=8.8.4.4 --name myapp nginx:alpine
```

### Real-world use case
Microservices zinazohitaji ku-*discover* huduma nyingine bila ku-*hardcode* IP addresses (ambazo zinabadilika kila container inapo-restart) — DNS-based discovery ndiyo msingi wa jinsi Docker Compose na Swarm zinavyofanya kazi.

---

## 1.8 Port Publishing

### Nadharia
Wakati container iko kwenye bridge network, huwezi kuifikia moja kwa moja kutoka nje ya host (isipokuwa uko kwenye network hiyo hiyo). **Port publishing** (`-p`) inaunda `iptables` DNAT (Destination NAT) rule inayo-*forward* trafiki kutoka port fulani ya host kwenda port ya container.

### Aina za `-p` syntax

```bash
# Publish port 8080 ya host -> port 80 ya container
docker run -d -p 8080:80 nginx:alpine

# Publish kwenye interface maalum tu (mfano localhost pekee, si dunia yote)
docker run -d -p 127.0.0.1:8080:80 nginx:alpine

# Publish port ya container kwenye random port ya host (Docker itachagua)
docker run -d -p 80 nginx:alpine
docker port <container_id>   # kuona port iliyochaguliwa

# Publish range ya ports
docker run -d -p 8000-8010:8000-8010 myapp

# Publish UDP port
docker run -d -p 53:53/udp mydns

# PUBLISH ALL exposed ports (zilizotajwa kwenye Dockerfile EXPOSE) kwenye random ports
docker run -d -P nginx:alpine
```

### Kuangalia mapping halisi

```bash
docker ps
# Utaona: 0.0.0.0:8080->80/tcp, :::8080->80/tcp

docker port <container_name_au_id>
# 80/tcp -> 0.0.0.0:8080
```

### Muhimu kuelewa kwa kina
`-p 8080:80` HAITUMII `EXPOSE` iliyoko kwenye Dockerfile. `EXPOSE` ni **documentation tu** (inamwambia mtu anayesoma Dockerfile "hii image inasikiliza port hii") — haifungui port yoyote kiuhalisia. Ndiyo maana `-P` (herufi kubwa) inatumia taarifa za `EXPOSE` kuamua ni ports zipi za ku-publish, lakini `-p` (herufi ndogo) unaamua wewe moja kwa moja bila kujali `EXPOSE`.

### Real-world use case
Kuendesha web server nyingi kwenye seva moja, kila moja kwenye port tofauti ya host, ili reverse proxy (kama Nginx au Traefik) iwaelekeze kulingana na domain:

```bash
docker run -d -p 3001:3000 --name app1 myapp:v1
docker run -d -p 3002:3000 --name app2 myapp:v2
```

---

## 1.9 Network Isolation

### Nadharia
Network isolation ni dhana ya kuhakikisha containers/services zinazoongea zinaruhusiwa TU kuongea na kile kinachohitajika — kuzuia "lateral movement" endapo container moja itavamiwa (compromised).

### Mbinu za kiuhalisia

**(a) Kutenganisha kwa multiple networks**

```bash
docker network create frontend-net
docker network create backend-net

# Web server: inaonekana kwa frontend NA backend
docker run -d --name web --network frontend-net nginx:alpine
docker network connect backend-net web

# Database: PEKEE kwenye backend - haiwezi kufikiwa na dunia ya nje kabisa
docker run -d --name db --network backend-net postgres:16
```

Hapa, `db` haipo kwenye `frontend-net` kabisa — hakuna njia ya kuifikia kutoka internet, hata kama mtu atapata ufikiaji wa `web` container, atalazimika kwanza avunje `web` ndipo aweze kufikia `backend-net`.

**(b) Internal network (bila internet access kabisa)**

```bash
docker network create --internal secure-backend
docker run -d --name db --network secure-backend postgres:16
```

Network ya `--internal` haina route ya nje kabisa (hakuna default gateway ya internet) — containers zinaweza kuongea zenyewe kwa zenyewe TU, hazina uwezo wa outbound internet access. Hii ni muhimu sana kwa database ambayo haipaswi kamwe ku-*exfiltrate* data kwenda internet hata kama itavamiwa.

**(c) `docker-compose.yml` na multiple isolated networks (mfano kamili wa 3-tier app)**

```yaml
services:
  nginx:
    image: nginx:alpine
    ports:
      - "443:443"
    networks:
      - public

  api:
    image: myapi:latest
    networks:
      - public
      - private

  db:
    image: postgres:16
    networks:
      - private   # HAIPO kwenye 'public' - haiwezi kufikiwa kutoka nje

networks:
  public:
  private:
    internal: true
```

Muundo huu: `nginx` inaonekana kwa dunia (`public`), inaongea na `api` (ambayo iko kwenye networks zote mbili), na `api` pekee ndiye anayeweza kuongea na `db` (ambayo iko kwenye `private` isiyo na internet access). Hii ni **defense in depth** halisi.

---

# SEHEMU YA 2: DOCKER REGISTRY

## 2.1 Docker Hub

### Nadharia
Docker Hub ni public registry kuu ya Docker (registry.hub.docker.com) — hapa ndipo images rasmi (official images kama `nginx`, `postgres`, `python`) zinapatikana. Kila unapoandika `docker pull nginx`, Docker inatafuta kwenye Docker Hub kama huna registry nyingine iliyoainishwa.

### Mfano halisi

```bash
# Login
docker login
# Weka username na password (au access token - inashauriwa zaidi ya password)

# Tengeneza image yako
docker build -t yourusername/myapp:v1.0 .

# Push kwenda Docker Hub
docker push yourusername/myapp:v1.0

# Pull kutoka mahali pengine
docker pull yourusername/myapp:v1.0
```

**Muhimu**: jina la image lazima liwe na format `username/repo-name:tag` unapotuma kwa Docker Hub (isipokuwa images rasmi ambazo hazina prefix ya username).

### Access Token badala ya Password
Docker Hub inashauri kutumia **Personal Access Token (PAT)** badala ya password yako halisi (hasa kwenye CI/CD):

1. Nenda Docker Hub → Account Settings → Security → New Access Token
2. Tumia token hiyo:
```bash
echo "$DOCKER_TOKEN" | docker login -u yourusername --password-stdin
```

### Rate Limits
Docker Hub ina **pull rate limits** kwa anonymous/free accounts (mfano: 100 pulls kwa masaa 6 kwa anonymous). Hii ni sababu kubwa kwa nini makampuni mengi yanatumia private registries au mirror za ndani kwa production.

---

## 2.2 Private Registry (self-hosted)

### Nadharia
Unaweza kuendesha registry yako mwenyewe kwa kutumia image rasmi `registry:2` (inaitwa pia "Distribution"). Hii ni muhimu kwa makampuni yanayotaka udhibiti kamili wa images zao (usalama, gharama, uhuru wa network).

### Mfano halisi - kuanzisha private registry

```bash
# Anzisha registry kwenye port 5000, na persistent storage
docker run -d -p 5000:5000 --name my-registry \
  -v registry-data:/var/lib/registry \
  registry:2
```

Tumia registry hii:

```bash
docker pull alpine:latest
docker tag alpine:latest localhost:5000/alpine:latest
docker push localhost:5000/alpine:latest

# Kisha thibitisha inafanya kazi
docker pull localhost:5000/alpine:latest
```

### Kuongeza TLS + Authentication (production-grade)

Registry ya production LAZIMA iwe na TLS (HTTPS) na authentication — Docker itakataa ku-push/pull kwenda registry isiyo na TLS isipokuwa umeiweka kwenye "insecure registries" list (siyo salama kwa production).

```bash
# Tengeneza htpasswd file kwa basic auth
mkdir auth
docker run --entrypoint htpasswd httpd:2 -Bbn myuser mypassword > auth/htpasswd

# Endesha registry na TLS + auth
docker run -d -p 5000:5000 --name secure-registry \
  -v $(pwd)/auth:/auth \
  -e "REGISTRY_AUTH=htpasswd" \
  -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
  -e "REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd" \
  -v $(pwd)/certs:/certs \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  registry:2

docker login myregistry.example.com:5000 -u myuser -p mypassword
```

### Real-world use case
Kampuni yenye source code za siri (proprietary) haitaki images zake ziwe public kwenye Docker Hub — inaendesha private registry ndani ya VPC yake (mfano kwenye Kubernetes cluster yao) na kuzuia ufikiaji kwa VPN/firewall pekee.

---

## 2.3 Amazon ECR (Elastic Container Registry)

### Nadharia
ECR ni managed container registry ya AWS, inayounganika moja kwa moja na IAM (permissions), ECS, EKS na Fargate.

### Mfano halisi

```bash
# Authenticate Docker kwa ECR (token inadumu masaa 12 tu)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com

# Tengeneza repository
aws ecr create-repository --repository-name myapp --region us-east-1

# Tag na push
docker tag myapp:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:latest
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:latest
```

### Vipengele muhimu vya ECR
* **Image scanning** ya kiotomatiki (kutumia Clair) kila unapo-push image — inaonyesha vulnerabilities (CVEs) moja kwa moja.
* **Lifecycle policies** za kufuta images za zamani kiotomatiki (kupunguza gharama za storage).
* **Cross-region/cross-account replication**.

```bash
# Kuwasha scan-on-push
aws ecr put-image-scanning-configuration \
  --repository-name myapp \
  --image-scanning-configuration scanOnPush=true
```

### Real-world use case
Timu inayoendesha workloads kwenye ECS/EKS — ECR inaunganika na IAM roles moja kwa moja, hakuna haja ya ku-manage credentials tofauti, na scanning inatoa taarifa za usalama automatically kwenye pipeline.

---

## 2.4 Azure Container Registry (ACR)

### Mfano halisi

```bash
az login
az acr create --resource-group myRG --name myacrregistry --sku Basic

az acr login --name myacrregistry

docker tag myapp:latest myacrregistry.azurecr.io/myapp:latest
docker push myacrregistry.azurecr.io/myapp:latest
```

ACR pia inatoa **ACR Tasks** — unaweza kuunda images moja kwa moja kwenye cloud (siyo kwenye laptop yako) kila mabadiliko ya code yanapotokea kwenye Git:

```bash
az acr build --registry myacrregistry --image myapp:v1 .
```

### Real-world use case
Timu zinazotumia Azure DevOps/AKS - ACR inaunganika moja kwa moja na Azure AD kwa authentication na AKS kwa deployment bila configuration ya ziada.

---

## 2.5 Google Artifact Registry

### Nadharia
Google Artifact Registry ni mrithi wa Google Container Registry (GCR) - inashughulikia siyo tu Docker images bali pia Maven, npm, Python packages, n.k - registry moja kwa vitu vyote.

### Mfano halisi

```bash
gcloud auth configure-docker us-central1-docker.pkg.dev

gcloud artifacts repositories create my-repo \
  --repository-format=docker \
  --location=us-central1

docker tag myapp:latest us-central1-docker.pkg.dev/my-project/my-repo/myapp:latest
docker push us-central1-docker.pkg.dev/my-project/my-repo/myapp:latest
```

### Real-world use case
Timu zinazotumia GKE (Google Kubernetes Engine) - Artifact Registry inatoa vulnerability scanning built-in na inaunganika na Binary Authorization (kuzuia deployment ya images zisizo na saini/verification).

---

## 2.6 Authentication kwa Registries (kwa ujumla)

Muhtasari wa mbinu tatu kuu:

1. **Username/Password** (`docker login`) — rahisi lakini si salama kwa CI/CD (credentials zinaweza ku-leak kwenye logs).
2. **Access Tokens/PATs** — bora zaidi, zinaweza ku-*revoke* bila kubadilisha password kuu.
3. **Cloud IAM Roles** (ECR/ACR/GAR) — bora zaidi, hakuna secret ya kudumu inayohifadhiwa, zinaisha muda (expire) automatically.

Config file inayotunza credentials (usiwahi ku-commit hii kwenye Git!):

```bash
cat ~/.docker/config.json
```

Kwa production, tumia **credential helpers** badala ya kuhifadhi plaintext passwords:

```bash
# Mfano: ECR credential helper
docker-credential-ecr-login
```

---

## 2.7 Image Signing

### Nadharia
Image signing inathibitisha kuwa image fulani IMETOKA kwa mtu/mfumo unayemwamini na HAIJABADILISHWA (tampered) tangu ilipo-build. Bila signing, mtu yeyote mwenye ufikiaji wa registry anaweza ku-push image mbaya (malicious) yenye jina lile lile.

### Mfano halisi na Cosign (chombo maarufu zaidi leo)

```bash
# Sakinisha cosign
brew install cosign   # au download kutoka GitHub releases

# Tengeneza key pair
cosign generate-key-pair
# Inatoa: cosign.key (private - tunza kwa siri) na cosign.pub (public - shiriki)

# Saini image baada ya kui-push
docker push myregistry.com/myapp:v1
cosign sign --key cosign.key myregistry.com/myapp:v1

# Verify signature (mtu mwingine anaweza kuthibitisha)
cosign verify --key cosign.pub myregistry.com/myapp:v1
```

Ukibadilisha image (mfano mtu mwingine ame-push tena kwa jina lile lile bila ruhusa), `cosign verify` itashindwa (fail) mara moja.

### Real-world use case
Kwenye Kubernetes cluster, unaweza kutumia **admission controller** (kama Kyverno au OPA Gatekeeper) kuzuia deployment ya images ambazo hazijasainiwa (unsigned) — hii ni sehemu muhimu ya "supply chain security".

---

## 2.8 Image Scanning

### Nadharia
Image scanning inachunguza layers zote za image kutafuta **known vulnerabilities (CVEs)** kwenye packages/libraries zilizosakinishwa ndani yake, kwa kulinganisha na databases kama NVD (National Vulnerability Database).

### Mfano halisi na Trivy

```bash
# Sakinisha trivy
brew install trivy   # au apt/yum kulingana na OS

# Scan image
trivy image nginx:latest
```

Matokeo yanaonyesha jedwali la vulnerabilities kwa severity (CRITICAL, HIGH, MEDIUM, LOW), na version gani ina fix.

```bash
# Scan na exit code isipokuwa (fail build) kama kuna CRITICAL
trivy image --severity CRITICAL --exit-code 1 myapp:latest
```

Hii amri ya mwisho ndiyo inayotumika kwenye CI/CD pipelines kuzuia deployment ya images zenye vulnerabilities hatari.

*(Tazama SEHEMU YA 3 kwa maelezo zaidi ya kina kuhusu scanning tools).*

---

## 2.9 Supply Chain Security (Registry context)

### Nadharia
"Software supply chain" ni safari nzima ya code — kutoka developer anapoandika, mpaka image inavyofika production. Kila hatua (dependencies, base images, build process, registry, deployment) ni sehemu inayoweza kushambuliwa (attack surface).

### Mbinu za kiuhalisia
1. **Pin base images kwa digest, si tag**:
```dockerfile
# Hatari - tag inaweza kubadilika bila taarifa
FROM node:18

# Salama - digest ni immutable, image hiyo hasa hasa
FROM node:18@sha256:a1b2c3d4e5f6...
```

2. **SBOM (Software Bill of Materials)** - orodha kamili ya kila kitu kilichomo ndani ya image yako (tazama sehemu 3.19 chini kwa mfano wa kina).

3. **Provenance attestation** - kuthibitisha *jinsi* image ilivyojengwa (build process gani, kwenye mfumo gani):
```bash
docker buildx build --provenance=true --sbom=true -t myapp:v1 .
```

---

# SEHEMU YA 3: CONTAINER SECURITY

## 3.1 CIS Docker Benchmark

### Nadharia
CIS (Center for Internet Security) Docker Benchmark ni hati (document) yenye mamia ya "best practice" checks zilizopangwa kikundi (host configuration, daemon configuration, container images, container runtime, n.k) — kila kimoja kina rating ya "Scored" au "Not Scored" na maelekezo ya jinsi ya kurekebisha.

Mfano wa checks chache halisi kutoka CIS Benchmark:
* 1.1.1 — Hakikisha kernel ina toleo jipya
* 4.1 — Hakikisha "USER" imeainishwa kwenye kila Dockerfile (siyo root)
* 5.4 — Hakikisha `--privileged` haitumiki
* 5.25 — Hakikisha `--pids-limit` imewekwa (kuzuia fork bombs)

---

## 3.2 Docker Bench for Security

### Nadharia
Hii ni script (open-source, kutoka Docker Inc na community) inayotekeleza (automate) checks nyingi za CIS Benchmark moja kwa moja kwenye mfumo wako, na kutoa ripoti ya PASS/WARN/INFO.

### Mfano halisi

```bash
docker run -it --net host --pid host --userns host --cap-add audit_control \
  -e DOCKER_CONTENT_TRUST=$DOCKER_CONTENT_TRUST \
  -v /etc:/etc:ro \
  -v /var/lib:/var/lib:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /usr/lib/systemd:/usr/lib/systemd:ro \
  --label docker_bench_security \
  docker/docker-bench-security
```

Utapata output ya kina yenye mistari kama:

```
[WARN] 2.1  - Ensure network traffic is restricted between containers on the default bridge
[PASS] 4.1  - Ensure a user for the container has been created
[WARN] 5.4  - Ensure privileged containers are not used
```

Kila `WARN` inakuonyesha hasa nini cha kurekebisha.

---

## 3.3 Trivy (kwa kina zaidi)

Trivy (na Aqua Security) ni scanner ya "all-in-one" — inaweza kuscan: container images, filesystems, Git repositories, Kubernetes clusters, na hata IaC files (Terraform, Kubernetes YAML) kwa misconfigurations.

```bash
# Scan Dockerfile kwa misconfigurations
trivy config ./Dockerfile

# Scan filesystem (kabla hujajenga image)
trivy fs .

# Scan kwa secrets zilizosahaulika (API keys, passwords zilizo-hardcode)
trivy image --scanners secret myapp:latest

# Generate SBOM moja kwa moja
trivy image --format cyclonedx --output sbom.json myapp:latest
```

---

## 3.4 Grype

### Nadharia
Grype (kutoka Anchore) ni mbadala wa Trivy - inafanya kazi sawa (vulnerability scanning) lakini na database yake tofauti — vizuri kuitumia PAMOJA na Trivy kama "second opinion" kwa sababu hakuna scanner moja inayogundua kila kitu.

```bash
grype myapp:latest

# Fail CI kama kuna vulnerabilities za High au juu zaidi
grype myapp:latest --fail-on high
```

---

## 3.5 Docker Scout

### Nadharia
Docker Scout ni tool rasmi ya Docker (imejumuishwa kwenye Docker Desktop) inayochunguza images kwa vulnerabilities na kutoa "recommendations" za jinsi ya kupunguza (mfano: "badilisha base image kwenda `alpine` utapunguza vulnerabilities 15").

```bash
docker scout quickview myapp:latest
docker scout cves myapp:latest
docker scout recommendations myapp:latest

# Linganisha image mbili (mfano kabla na baada ya update)
docker scout compare myapp:v1 --to myapp:v2
```

---

## 3.6 Rootless Docker

### Nadharia
Kwa default, Docker daemon inaendesha kama **root** kwenye host — hii ina maana yeyote mwenye ufikiaji wa `docker.sock` ana uwezo sawa na root (privilege escalation risk kubwa sana, kwa sababu unaweza mount `/` ya host ndani ya container). **Rootless mode** inaruhusu Docker daemon yenyewe na containers zote kuendesha bila root privileges kabisa, kwa kutumia Linux user namespaces.

### Mfano halisi (kusakinisha)

```bash
# Ondoa Docker ya kawaida ya system (kama ipo) au tumia parallel install
curl -fsSL https://get.docker.com/rootless | sh

# Endesha kama user wa kawaida (siyo root/sudo)
export PATH=/home/$USER/bin:$PATH
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock

dockerd-rootless-setuptool.sh install

systemctl --user start docker
docker run hello-world
```

Sasa hata kama attacker atatoroka (escape) kutoka ndani ya container, ataishia kuwa user wa kawaida asiye na privileges kwenye host — siyo root.

---

## 3.7 Secrets Management

### Nadharia
Kamwe usiweke secrets (passwords, API keys, certificates) kwenye:
* Dockerfile (`ENV DB_PASSWORD=12345`) — inabaki kwenye image layers milele, hata ukiifuta baadaye kwenye layer nyingine.
* Environment variables kwenye `docker run -e` — zinaonekana kwa `docker inspect`, na kwa michakato yote ndani ya container (`/proc/1/environ`).

### Mbinu sahihi - Docker Secrets (kwenye Swarm)

```bash
echo "SuperSecretPassword123" | docker secret create db_password -

docker service create --name db \
  --secret db_password \
  -e POSTGRES_PASSWORD_FILE=/run/secrets/db_password \
  postgres:16
```

Secret inasomwa kutoka faili `/run/secrets/db_password` ndani ya container (**in-memory tmpfs**, si diski), na haionekani kamwe kwenye `docker inspect` au image layers.

### Docker Compose secrets (kwa local development)

```yaml
services:
  db:
    image: postgres:16
    secrets:
      - db_password
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password

secrets:
  db_password:
    file: ./db_password.txt   # faili hii isiwe ndani ya Git!
```

Kwa production ya kweli, tumia vault za nje kama **HashiCorp Vault**, **AWS Secrets Manager**, au **Azure Key Vault** badala ya kutegemea Docker secrets pekee.

---

## 3.8 Least Privilege

### Nadharia
Kanuni ya "Least Privilege" - mpe container/process ruhusa ndogo zinazohitajika tu kufanya kazi yake, hakuna zaidi.

### Mifano halisi ya kutekeleza

```bash
# 1. Read-only root filesystem - container haiwezi kuandika popote isipokuwa volumes zilizoainishwa
docker run --read-only -v /app/tmp:/app/tmp myapp:latest

# 2. Drop capabilities zote, ongeza tu unazohitaji
docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE myapp:latest

# 3. Zuia resource abuse (fork bombs, memory exhaustion)
docker run --pids-limit=100 --memory=512m --cpus=1 myapp:latest

# 4. Zuia privilege escalation ndani ya container
docker run --security-opt=no-new-privileges myapp:latest
```

---

## 3.9 Distroless Images

### Nadharia
"Distroless" images (kutoka Google) hazina shell (`sh`/`bash`), package manager, wala tools zozote za ziada — zina TU application yako na runtime dependencies zake za msingi. Hii inapunguza sana **attack surface** (kwa sababu attacker akipata RCE (remote code execution), hana hata `sh` ya kutumia kuendesha amri zaidi).

### Mfano halisi (multi-stage build)

```dockerfile
# Stage 1: Build
FROM golang:1.22 AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o myapp .

# Stage 2: Distroless - image ya mwisho ni ndogo sana na salama zaidi
FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/myapp /myapp
USER nonroot:nonroot
ENTRYPOINT ["/myapp"]
```

Linganisha size:
```bash
docker build -t myapp:distroless .
docker images myapp:distroless
# Mfano: 8MB tu, badala ya 900MB+ ya image ya kawaida ya golang
```

Huwezi hata ku-`docker exec -it myapp sh` kwenye distroless image kwa sababu shell haipo kabisa — hii ni feature, si bug!

---

## 3.10 Non-root Containers

### Nadharia
Kwa default, michakato ndani ya container inaendesha kama **root (UID 0)** ndani ya container - hata kama sio root kwenye host, bado ina ruhusa kubwa mno ndani ya container namespace, na kama kuna **container escape vulnerability**, root ndani inaweza kuwa root nje pia.

### Mfano halisi (Dockerfile)

```dockerfile
FROM node:18-alpine

# Tengeneza user asiye root
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app
COPY --chown=appuser:appgroup . .
RUN npm install

USER appuser

CMD ["node", "server.js"]
```

Thibitisha:
```bash
docker run --rm myapp:latest whoami
# appuser (siyo root!)
```

Unaweza pia kulazimisha hii wakati wa `docker run` bila kubadilisha Dockerfile:

```bash
docker run --user 1000:1000 myapp:latest
```

---

## 3.11 Linux Capabilities

### Nadharia
Badala ya "root ana kila kitu, mtumiaji wa kawaida hana kitu", Linux kernel inagawanya root privileges kwenye **capabilities** ndogo ndogo (mfano `NET_BIND_SERVICE` kufunga ports chini ya 1024, `CHOWN` kubadilisha umiliki wa faili, `SYS_ADMIN` - capability hatari zaidi, inatoa mamlaka mengi kama root kamili).

Docker kwa default inatoa capabilities ~14 tu (siyo zote ~40) kwa containers.

### Mfano halisi

```bash
# Ona capabilities za default
docker run --rm alpine sh -c "apk add libcap; capsh --print"

# Ondoa zote, ongeza moja tu inayohitajika (mfano: web server inayosikiliza port 80)
docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE -p 80:80 nginx:alpine

# EPUKA hii - hatari sana - inatoa capabilities ZOTE + zaidi
docker run --privileged myapp:latest   # USIFANYE kwenye production!
```

---

## 3.12 Seccomp

### Nadharia
Seccomp (secure computing mode) inazuia ni **syscalls** (system calls) gani container inaweza kuita kwenye kernel. Docker inatumia default seccomp profile inayozuia ~44 hatari syscalls (kama `reboot`, `mount`, `ptrace`) kati ya ~300+ zilizopo.

### Mfano halisi

```bash
# Tumia default seccomp profile (already default, lakini kuonyesha wazi)
docker run --security-opt seccomp=default.json myapp:latest

# Zuia kabisa seccomp (HATARI - usifanye)
docker run --security-opt seccomp=unconfined myapp:latest
```

Tengeneza custom seccomp profile (mfano kuzuia hata zaidi ya default):

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "syscalls": [
    {
      "names": ["read", "write", "open", "close", "exit", "exit_group"],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

```bash
docker run --security-opt seccomp=custom-profile.json myapp:latest
```

Profile hii inaruhusu TU syscalls sita zilizoorodheshwa — kila kitu kingine kitakataliwa (`errno` itarudishwa). Hii ni "allowlist" model - sahihi zaidi kuliko "denylist".

---

## 3.13 AppArmor

### Nadharia
AppArmor (kwenye Ubuntu/Debian - kwenye RHEL/CentOS wanatumia SELinux badala yake) ni Mandatory Access Control (MAC) system inayodhibiti ni faili zipi, ni network access ipi, na ni capabilities zipi process inaweza kutumia — kwa mtazamo tofauti na seccomp (ambayo ni syscall-level, AppArmor ni file/resource-level).

### Mfano halisi

```bash
# Angalia AppArmor profile ya default ya Docker
cat /etc/apparmor.d/docker-default

# Tumia profile maalum
docker run --security-opt apparmor=docker-default myapp:latest
```

Tengeneza profile yako:

```
# /etc/apparmor.d/my-custom-profile
profile my-custom-profile flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  network,
  deny /etc/shadow r,
  deny /root/** rwx,
  /app/** r,
}
```

```bash
sudo apparmor_parser -r /etc/apparmor.d/my-custom-profile
docker run --security-opt apparmor=my-custom-profile myapp:latest
```

Profile hii inakataza kabisa kusoma `/etc/shadow` na kufikia `/root/` ndani ya container, hata kama process ina root privileges.

---

## 3.14 Runtime Security (kwa ujumla)

### Nadharia
"Runtime security" ni kutambua tabia mbaya (malicious behavior) **wakati** container inaendesha (siyo tu kabla ya deployment kama image scanning). Hii inashughulikia kesi kama: container inayojaribu ku-*spawn* shell isiyotarajiwa, kufungua network connection kwenda IP ya kutiliwa shaka, au kusoma faili nyeti bila sababu.

Zana kuu: **Falco** (tazama sehemu inayofuata).

---

## 3.15 Falco

### Nadharia
Falco (kutoka Sysdig, sasa CNCF project) ni runtime security tool inayofuatilia (monitor) kernel events (kupitia eBPF au kernel module) na kutoa **alert ya real-time** endapo tabia inayoshukiwa itatokea, kwa kutumia rules zilizoainishwa.

### Mfano halisi

```bash
docker run -d --name falco \
  --privileged \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /dev:/host/dev \
  -v /proc:/host/proc:ro \
  -v /boot:/host/boot:ro \
  -v /lib/modules:/host/lib/modules:ro \
  -v /usr:/host/usr:ro \
  falcosecurity/falco:latest
```

Mfano wa rule ya Falco (default rules ziko `/etc/falco/falco_rules.yaml`):

```yaml
- rule: Terminal shell in container
  desc: A shell was spawned inside a container
  condition: >
    spawned_process and container and
    shell_procs and proc.tty != 0
  output: >
    Shell spawned in container (user=%user.name container=%container.name
    shell=%proc.name parent=%proc.pname)
  priority: WARNING
```

Rule hii itatoa alert mara moja mtu (au attacker) akijaribu kufungua `bash`/`sh` ndani ya production container — kitu ambacho kwa kawaida hakipaswi kutokea kwenye microservice iliyowekwa vizuri.

```bash
docker logs falco
# Utaona alerts za real-time endapo kuna tabia ya kutiliwa shaka
```

---

## 3.16 SBOM (Software Bill of Materials)

### Nadharia
SBOM ni orodha kamili (kama "ingredient list" ya chakula) ya kila component (libraries, packages, versions) zilizopo ndani ya image yako. Inasaidia sana wakati vulnerability mpya inagunduliwa (mfano Log4Shell) — badala ya kuscan kila image upya, unaweza tu ku-*query* SBOMs zako zote kuona ni zipi zinatumia library husika.

### Mfano halisi na Syft (tool maarufu ya kutengeneza SBOM)

```bash
syft myapp:latest -o cyclonedx-json > sbom.json
syft myapp:latest -o spdx-json > sbom-spdx.json

# Angalia muhtasari
syft myapp:latest
```

Matokeo yanaonyesha jedwali kama:

```
NAME          VERSION    TYPE
express       4.18.2     npm
lodash        4.17.21    npm
openssl       3.0.11     deb
```

Kutumia SBOM hii kuscan vulnerabilities:

```bash
grype sbom:./sbom.json
```

---

## 3.17 Cosign (kwa kina zaidi)

Tayari tumeona `cosign sign`/`cosign verify` kwenye Sehemu 2.7. Cosign pia inaweza ku-attach SBOM kama "attestation" iliyosainiwa moja kwa moja kwenye image kwenye registry:

```bash
cosign attest --key cosign.key --predicate sbom.json --type cyclonedx myapp:latest

# Verify attestation
cosign verify-attestation --key cosign.pub myapp:latest
```

Hii inamaanisha SBOM yenyewe pia ina uthibitisho wa uhalisia (siyo tu image).

---

## 3.18 Sigstore

### Nadharia
Sigstore ni mradi mkubwa (unaomiliki Cosign) unaolenga kufanya software signing kuwa **rahisi na bure** kwa kila mtu, kwa kutumia **keyless signing**. Badala ya kutunza private key mwenyewe (hatari ya kuipoteza au kuiba), Sigstore inatumia **OIDC identity** (mfano GitHub/Google account yako) kutengeneza short-lived certificate kila unapo-sign, na kila signing inarekodiwa kwenye transparency log ya umma (**Rekor**) isiyoweza kubadilishwa.

### Mfano halisi - Keyless signing

```bash
# Hakuna key ya kutunza! Cosign itakuomba u-login kwa GitHub/Google
cosign sign myregistry.com/myapp:v1

# Itafungua browser, uthibitishe identity yako (mfano GitHub OIDC)
# Signature + certificate zinahifadhiwa kwenye Rekor transparency log

# Verify (mtu yeyote anaweza kuthibitisha, hata bila key)
cosign verify \
  --certificate-identity=you@example.com \
  --certificate-oidc-issuer=https://github.com/login/oauth \
  myregistry.com/myapp:v1
```

### Real-world use case
Miradi mikubwa ya open-source (mfano Kubernetes yenyewe) inatumia Sigstore kuthibitisha kila release binary/image inatoka kwa build pipeline rasmi (siyo attacker aliyeiba maintainer account), bila kila mtu kulazimika kutunza private keys ngumu kudhibiti.

---

# MUHTASARI WA MWISHO — Defense in Depth kwa Container

Ukichanganya kila kitu tulichojifunza, container ya production "iliyokamilika" (hardened) inaonekana hivi:

```dockerfile
# 1. Multi-stage build - distroless final image
FROM golang:1.22 AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o myapp .

FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/myapp /myapp
USER nonroot:nonroot          # 2. Non-root
ENTRYPOINT ["/myapp"]
```

```bash
# 3. Scan kabla ya push
trivy image --severity CRITICAL,HIGH --exit-code 1 myapp:v1

# 4. Generate SBOM
syft myapp:v1 -o cyclonedx-json > sbom.json

# 5. Push kwenda private registry (na TLS+auth)
docker push myregistry.com/myapp:v1

# 6. Sign kwa keyless signing
cosign sign myregistry.com/myapp:v1
cosign attest --predicate sbom.json --type cyclonedx myregistry.com/myapp:v1

# 7. Run na hardening kamili
docker run -d \
  --name myapp \
  --network private-backend \
  --read-only \
  --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  --security-opt=no-new-privileges \
  --security-opt seccomp=default.json \
  --pids-limit=100 \
  --memory=512m \
  --cpus=1 \
  myregistry.com/myapp:v1
```

Falco inaendelea kufuatilia runtime, Docker Bench inatumika mara kwa mara ku-audit host, na network isolation (private/internal networks) inahakikisha container hii haiwezi kufikiwa moja kwa moja kutoka internet.

---

## Mazoezi Yanayopendekezwa (Practice)

1. Tengeneza networks tatu (`frontend`, `backend`, `internal`) na containers 3-4, jaribu kuthibitisha isolation kwa `docker exec ... ping`.
2. Simamisha (setup) private registry yako mwenyewe kwa TLS + auth, push/pull images.
3. Chukua image yoyote ya production (mfano `node:18`) na uiscan kwa Trivy — angalia CVEs zilizopo, kisha badilisha kwenda `node:18-alpine` au distroless, scan tena, linganisha.
4. Tengeneza Dockerfile yenye non-root user + distroless, endesha na `--cap-drop=ALL --read-only`, jaribu kuvunja (break) na uone kinachoshindwa kufanya kazi (hii inakufundisha nini hasa privileges zinahitajika).
5. Sakinisha Falco kwenye test VM, jaribu `docker exec -it <container> sh` na uone alert ikitokea.
