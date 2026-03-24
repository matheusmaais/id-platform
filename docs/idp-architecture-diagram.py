from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import ALB, CloudFront, Route53
from diagrams.aws.database import Aurora
from diagrams.aws.storage import S3
from diagrams.aws.security import Cognito, ACM
from diagrams.aws.compute import EKS
from diagrams.k8s.compute import Pod
from diagrams.k8s.network import Ingress
from diagrams.custom import Custom
import os
import urllib.request

icons_dir = "/tmp/diagram-icons"
os.makedirs(icons_dir, exist_ok=True)

icon_urls = {
    "argocd": "https://raw.githubusercontent.com/cncf/artwork/main/projects/argo/icon/color/argo-icon-color.png",
    "crossplane": "https://raw.githubusercontent.com/cncf/artwork/main/projects/crossplane/icon/color/crossplane-icon-color.png",
    "backstage": "https://raw.githubusercontent.com/cncf/artwork/main/projects/backstage/icon/color/backstage-icon-color.png",
    "prometheus": "https://raw.githubusercontent.com/cncf/artwork/main/projects/prometheus/icon/color/prometheus-icon-color.png",
    "github": "https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png",
    "karpenter": "https://raw.githubusercontent.com/cncf/artwork/main/projects/karpenter/icon/color/karpenter-icon-color.png",
}

icons = {}
for name, url in icon_urls.items():
    path = os.path.join(icons_dir, f"{name}.png")
    if not os.path.exists(path):
        try:
            urllib.request.urlretrieve(url, path)
        except Exception:
            pass
    icons[name] = path

output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "idp-architecture")

with Diagram(
    "",
    filename=output_path,
    show=False,
    direction="TB",
    outformat="png",
    graph_attr={
        "fontsize": "18",
        "fontname": "Helvetica",
        "bgcolor": "white",
        "pad": "0.5",
        "nodesep": "0.6",
        "ranksep": "0.8",
        "label": "Darede IDP — Internal Developer Platform\nus-east-1  •  timedevops.click  •  platform-eks",
        "labelloc": "t",
        "labeljust": "c",
    },
):
    # ── Row 1: Users & External ──
    cognito = Cognito("Cognito\nOIDC SSO")
    github = Custom("GitHub", icons["github"])
    dns = Route53("Route 53")
    acm = ACM("ACM TLS")

    with Cluster("VPC"):

        with Cluster("Public Subnets"):
            cf = CloudFront("CloudFront\nCDN + API Proxy")
            alb = ALB("ALB")

        with Cluster("EKS Cluster  —  K8s 1.31  —  Karpenter Spot ARM64"):

            with Cluster("Platform Control Plane"):
                backstage = Custom("Backstage", icons["backstage"])
                argocd = Custom("ArgoCD\nv3.2.6", icons["argocd"])
                crossplane = Custom("Crossplane\nv2.3.0", icons["crossplane"])

            with Cluster("Platform Addons"):
                prom = Custom("Prometheus", icons["prometheus"])
                karpenter = Custom("Karpenter", icons["karpenter"])
                extdns = EKS("External-DNS")
                lbc = EKS("LB Controller")
                eso = EKS("Ext Secrets")
                kubecost = EKS("Kubecost")

            with Cluster("App Workload (3-Tier)", graph_attr={"style": "dashed", "color": "#FF9900", "penwidth": "2"}):
                ingress = Ingress("Ingress\napi-{app}.timedevops.click")
                app = Pod("Backend\nExpress :3000")

        with Cluster("Crossplane-Provisioned"):
            aurora = Aurora("Aurora PostgreSQL\ndb.t4g.medium")
            s3 = S3("S3 Frontend")

    # ── Auth ──
    cognito >> Edge(style="dotted", color="#DD344C", label="OIDC") >> backstage
    cognito >> Edge(style="dotted", color="#DD344C") >> argocd

    # ── Developer flow ──
    backstage >> Edge(style="dashed", color="gray", label="scaffold") >> github
    github >> Edge(style="dashed", color="gray", label="webhook") >> argocd

    # ── GitOps ──
    argocd >> Edge(color="#18BE94", label="sync") >> app
    argocd >> Edge(color="#18BE94", label="sync") >> crossplane

    # ── Crossplane provisions ──
    crossplane >> Edge(color="#FF9900", label="provision") >> aurora
    crossplane >> Edge(color="#FF9900") >> s3

    # ── Traffic flow ──
    dns >> cf
    dns >> alb
    acm - Edge(style="dotted") - cf
    cf >> Edge(label="static") >> s3
    cf >> Edge(label="/api/*") >> alb
    alb >> ingress >> app

    # ── Data ──
    app >> Edge(color="#3B48CC", label="SQL :5432") >> aurora

    # ── Platform wiring ──
    extdns >> Edge(style="dotted", color="gray") >> dns
    lbc >> Edge(style="dotted", color="gray") >> alb
