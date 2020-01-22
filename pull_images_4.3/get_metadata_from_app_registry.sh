# !/bin/bash

# Source: openshift-qe
# http://git.app.eng.bos.redhat.com/git/openshift-misc.git/plain/jenkins/v4-image-test/app_registry_tools/

set -e
WORK_DIR=$PWD
REPO_TOP_DIR="$PWD/tempdir"
MANIFESTS_DIR="$REPO_TOP_DIR/manifests"
USE_LATEST=true
NAMESPACE=${1:-redhat-operators-art}
VERSION=${2:-all}
echo "#############Usage #############"
echo "\$1 namspace  \$2: version [all, 4.x , 4.2-s390x ]  \$3 : reponame \$4: reponame ...."
echo " getOperatorSourceMetadata.sh  redhat-operators-art 4.3  elasticsearch-operator cluster-logging"
echo "#############Usage End #############"

if [[ "X$3" == "X" ]];then 

   case $VERSION in
   4.1 )
       REPOSITORYS="elasticsearch-operator cluster-logging openshifttemplateservicebroker openshiftansibleservicebroker"
       ;;
   4.2 ) 
       REPOSITORYS="elasticsearch-operator cluster-logging openshifttemplateservicebroker openshiftansibleservicebroker local-storage-operator metering-ocp nfd"
       ;;
   4.3 ) 
       REPOSITORYS="elasticsearch-operator cluster-logging openshifttemplateservicebroker openshiftansibleservicebroker local-storage-operator metering-ocp nfd"
       ;;
   4.4 ) 
       REPOSITORYS="elasticsearch-operator cluster-logging local-storage-operator metering-ocp nfd"
       ;;
   *) 
       REPOSITORYS="elasticsearch-operator cluster-logging"
       ;;
   esac 
else
    shift;shift
    REPOSITORYS=$*
fi

#REPOSITORYS="elasticsearch-operator cluster-logging"
#REPOSITORYS="sriov-network-operator"

rm -rf "${MANIFESTS_DIR}"
mkdir -p "$REPO_TOP_DIR"
mkdir -p "${MANIFESTS_DIR}"

cat <<EOF > "${REPO_TOP_DIR}/get_images_from_app_registry.py"
#
# The operators manifest. Extract Images from clusterversion bundle
# Authors:
#       Anping Li <anli@redhat.com>
#
# -*- coding: utf8 -*-
import re
import os
import yaml
import argparse
import commands
import tempfile
import logging
import traceback


class OlmManifest():
    def __init__(self, repo):
        self.name=""  #package name
        self.repo=repo
        self.default_channel=""
        self.package=None
        self.channels=[]
        self.cluster_service_versions=[]
        self.__build_bundle_data()
        self.__set_variables()
       
    def __set_variables(self):
        self.name=self.package['packageName']
        for channel in self.package["channels"]:
            self.channels.append(channel['name'])
        if ( "defaultChannel" in self.package):
            self.default_channel=self.package['defaultChannel']

    def get_images_by_channel(self, version):
        images=[]
        dest_csv=None
        dest_csv_name=""
        
        for ch in self.package["channels"]:
            if (version==ch["name"]):
                 dest_csv_name=ch["currentCSV"]
        for csv in self.cluster_service_versions:
	    if (csv["metadata"]["name"] == dest_csv_name):
                for item_deployment in  csv['spec']['install']['spec']['deployments']:
                    for item_container in item_deployment["spec"]["template"]['spec']["containers"]:
                        images.append(item_container['image'])
                        if('env' in item_container):
                            for  item_env in item_container['env']:
                                if(re.search("_IMAGE", item_env['name'])):
                                    if item_env['value'] not in images:
                                        images.append(item_env['value'])
                                if(item_env['name'] == "IMAGE"):
                                    if item_env['value'] not in images:
                                        images.append(item_env['value'])
	if(len(images)==0):
            images=self.get_images_by_version(version)
        return images
        
    def get_images_by_version(self, version):
        images=[] 
        dest_csv=None
        for csv in self.cluster_service_versions:
            if re.match(version,csv['spec']['version']):
                 dest_csv=csv
        if(dest_csv):
            for item_deployment in  dest_csv['spec']['install']['spec']['deployments']:
                for item_container in item_deployment["spec"]["template"]['spec']["containers"]:
                    images.append(item_container['image'])
                    if('env' in item_container):
                        for  item_env in item_container['env']:
                            if(re.search("_IMAGE", item_env['name'])):
                                if item_env['value'] not in images:
                                    images.append(item_env['value'])
        return images

    def get_images_all(self):
        images=[] 
        for csv in self.cluster_service_versions:
            for item_deployment in  csv['spec']['install']['spec']['deployments']:
                for item_container in item_deployment["spec"]["template"]['spec']["containers"]:
                    images.append(item_container['image'])
                    if('env' in item_container):
                        for  item_env in item_container['env']:
                            if(re.search("_IMAGE", item_env['name'])):
                                if item_env['value'] not in images:
                                    images.append(item_env['value'])
        return images
        
        
    def __build_bundle_data(self):
        repo_name=self.repo
        packages = [ f for f in os.listdir(repo_name) if re.match(".*package.", f) ]

        if(len(packages)== 1):
            logging.debug("found package.")
            csvs=[]
            f = open(os.path.join(repo_name,packages[0]))
            self.package=yaml.load(f)
            f.close()
            for r, d, f in os.walk(repo_name):
                for file in f:
                    if 'clusterserviceversion.' in file:
                        logging.debug("found clusterserviceversion.")
                        f = open(os.path.join(r, file))
                        self.cluster_service_versions.append(yaml.load(f))
                        f.close()
            return True

        bundles = [ f for f in os.listdir(repo_name) if re.match(".*bundle.", f) ]
        if(len(bundles)== 1):
            logging.debug("found bundle.")
            f = open(os.path.join(repo_name,bundles[0]))
            bundle=yaml.load(f)
            f.close()
            self.package=yaml.load(bundle['data']['packages'])[0]
            self.cluster_service_versions.append(yaml.load(bundle['data']['clusterServiceVersions']))
            return True
        logging.error("Neither bundle. and clusterserviceversion.yaml ")
        return False


parser = argparse.ArgumentParser()
parser.add_argument('-r', '--repo_dir', type=str,required=True )
parser.add_argument('-v', '--version', type=str)
args=parser.parse_args()
images=[]

csv_bundle=OlmManifest(args.repo_dir)
if(args.version and re.match("4\.\d+$",args.version)):
        images=csv_bundle.get_images_by_channel(args.version)
else:
    logging.warning("Get All images")
    images=csv_bundle.get_images_all()

for image in images:
    print image

EOF

function getQuayToken()
{
   echo "##get Quay Token"
   Quay_Token=$(curl -s -H "Content-Type: application/json" -XPOST https://quay.io/cnr/api/v1/users/login -d ' { "user": { "username": "anli", "password": "5Lg1uyX1UWOwEo217nOtWYj1eigAvfz2I4SZszyugIxcItEtQrGeUFv7TmeCUhbs" } }' |jq -r '.token')
   echo "$Quay_Token" > "${WORK_DIR}/quay.token"
}

function downloadRepos()
{  
    echo ""
    echo "#Download buldle.yaml from Operator source"
    repo=$1
    repo_dir="${REPO_TOP_DIR}/$repo"
    rm -rf "${repo_dir}"
    mkdir -p "${repo_dir}"
    cd "${repo_dir}"
    URL="https://quay.io/cnr/api/v1/packages/${NAMESPACE}/${repo}"
    echo "##Get buddle Version"
    curl -s -H "Content-Type: application/json" -H "Authorization: ${Quay_Token}" -XGET $URL |python -m json.tool > manifest.json
    if [[ $USE_LATEST = true ]] ; then
        echo  "##Use latest buddle version"
        release=$(jq -r '.[].release' manifest.json|sort -V |tail -1)
	echo "The version $release will be used "
    else
        releases=$(jq -r '.[].release' manifest.json)
        echo  ""
        echo "##Choose buddle version"
        echo  ""
        jq '.[].release ' manifest.json |tr  ["\n"] ' '
        echo  ""
        echo "##Please input one version to download"
        echo  ""
        read -s release
        match=false
        for version in ${releases}; do
             if [[ $release == $version ]];then
                 match=true
            fi
        done
        if [[ $match == flase ]]; then
            echo "#you must use version in the list"
            exit 1
        fi
	echo "##The version $release will be used "

    fi
    distget=$(jq -r --arg RELEASE "$release" '.[] | select(.release == $RELEASE).content.digest' manifest.json)
    echo "##Get  buddle_${release}.tar.gz"
    curl -s -H "Content-Type: application/json" -H "Authorization: ${Quay_Token}" -XGET $URL/blobs/sha256/$distget  -o buddle_${release}.tar.gz
    echo "##unzip  buddle_${release}.tar.gz"
    gunzip buddle_${release}.tar.gz
    tar -xvf buddle_${release}.tar
    manifest_dir=$(ls -1 "$repo_dir" |grep $repo)
    mv "$manifest_dir" "$MANIFESTS_DIR/$repo"
    cd "${WORK_DIR}"
    rm -rf "${repo_dir}"
}

function getImages()
{
    repo=$1
    local version=$2
    local "manifest_dir"="$MANIFESTS_DIR/$repo"
    python  "${REPO_TOP_DIR}/get_images_from_app_registry.py"  -r "$manifest_dir" -v $version
}

###########################Main##########################################
>"${WORK_DIR}/OperatorSource_CSV_Files.txt"
>"${WORK_DIR}/OperatorSource_Images_List.txt"
>"${WORK_DIR}/OperatorSource_Images_registry_proxy.txt"
>"${WORK_DIR}/OperatorSource_Images_version.txt"
getQuayToken
echo $REPOSITORYS
for repository in ${REPOSITORYS}; do
    echo ""
    echo "# Down load Manifest files"
    downloadRepos "${repository}"
    echo "# Get Image List"
    getImages "${repository}" $VERSION |tee -a "${WORK_DIR}/OperatorSource_Images_List.txt"
done

echo "--------------------------------"
echo "# Show image list in CSV"
echo "-------------------------------"
cat "${WORK_DIR}/OperatorSource_Images_List.txt"

if [[ SHOW_TAG ]];then
    echo "--------------------------------"
    echo "# Show image version for easy checking"
    echo "--------------------------------"
    cp OperatorSource_Images_List.txt OperatorSource_Images_registry_proxy.txt
    sed -i 's#image-registry.openshift-image-registry.svc:5000/openshift/#registry-proxy.engineering.redhat.com/rh-osbs/openshift-#' OperatorSource_Images_registry_proxy.txt
    for image in $(cat OperatorSource_Images_registry_proxy.txt);
    do
        echo "oc image info $image -o json --filter-by-os=linux/amd64 | jq -c -r '.config.config.Labels.version,.config.config.Labels.release'"
        image_labels=$(oc image info $image -o json --filter-by-os=linux/amd64 | jq -c -r '.config.config.Labels.version,.config.config.Labels.release')
        echo "$image:$image_labels" |tee -a OperatorSource_Images_version.txt
    done
fi
