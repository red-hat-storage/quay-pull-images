# !/bin/bash
# This script is used to sync images from registry-proxy.engineering.redhat.com to the internal cluster registry.
# Two type of images can be synced.
# 1) images list in files OperatorSource_Images_List.txt
# 2) staic images list in variable Static_Images
# Author: anli@redhat.com

# Source: openshift-qe
# http://git.app.eng.bos.redhat.com/git/openshift-misc.git/plain/jenkins/v4-image-test/app_registry_tools/

set -xe
Source_Registry=registry-proxy.engineering.redhat.com
Dest_Registry=""

Source_ImageList=OperatorSource_Images_List.txt
Image_Map_file=Image_Mapping.txt
Docker_Config_File=mirror_docker.conf

Static_Images="ose-logging-eventrouter"
# Image_Version is a global variable which will be set when generate the map list from Source_ImageList, which will be used as the tag of Static_Images
Image_Version=""

function gen_image_map_latest_tag()
{
    local source_image="$1"
    local dest_image="$2:latest"
    echo $source_image=$dest_image >>$Image_Map_file
}

function gen_image_map_accurate_tag()
{
    local source_image="$1"
    local dest_image="$2"
    local image_labels=$(oc image info $source_image --filter-by-os linux/amd64 -o json |jq '.config.config.Labels')

    if [[ "X$image_labels" != "X" ]]; then
        #image_name=openshift/ose-logging-fluentd
        image_name=$(echo $image_labels |jq -r '.name')
        #image_version=v4.1.0
        image_version=$(echo $image_labels |jq -r '.version')
        #image_release=201905101016
        image_release=$(echo $image_labels |jq -r '.release')

        if [[ $image_name =~ logging ]];then
            Image_Version=$image_version
        fi

	dest_image_version=$Dest_Registry/$image_name:$image_version
	dest_image_release=$Dest_Registry/$image_name:$image_version-${image_release}
        echo $source_image=$dest_image_version >>$Image_Map_file
        echo $source_image=$dest_image_release >>$Image_Map_file
    fi
}

function sync_images()
{
    echo "# Print registry status"
    oc get pod -n openshift-image-registry -l docker-registry=default
    echo "# The image mapping list"
    cat $Image_Map_file

    n=0
    until [ $n -ge 20 ]
    do
        echo "# oc image mirror --filename=$Image_Map_file --insecure=true -a $Docker_Config_File --skip-missing=true --skip-verification=true"
        oc image mirror --filename=$Image_Map_file --insecure=true -a $Docker_Config_File --skip-missing=true --skip-verification=true |& tee mirror_result.txt
        error_count=$(grep  -c 'error: one or more errors occurred while uploading images' mirror_result.txt)
      
        if [  $error_count -eq 0  ]; then
            break
        fi
        echo "try the $n time"
        n=$[$n+1]
        sleep 15 
    done
    
    if [ $error_count -eq 0  ]; then
       echo "# Info: Image Mirror Complete"
    else
       echo "# Warning: Some Images Mirror Failed"
    fi

}

function gen_static_images_map()
{
   echo "# Generate image mapping for static images"
   local image_name=$1
   local source_image="registry-proxy.engineering.redhat.com/rh-osbs/openshift-$image_name:$Image_Version"
   local dest_image_latest="${Dest_Registry}/openshift/$image_name:latest"
   
   oc image info $source_image --filter-by-os linux/amd64 >/dev/null
   if [[ $? == 0 ]]; then
       echo "registry-proxy.engineering.redhat.com/rh-osbs/openshift-$image_name:$Image_Version=${Dest_Registry}/openshift/$image_name:latest" >> "$Image_Map_file"
   else
        echo "# Warning: Skip $image_name:$Image_Version"
   fi 
   
}
function gen_image_map()
{
    echo "# Generate image mapping for csv images"
    >$Image_Map_file
    for image_url in $(cat ${Source_ImageList} | grep -v "quay.io" | sort |uniq ); do

	if [[ $Source_Registry == "registry-proxy.engineering.redhat.com" ]]; then
	    source_image=${image_url/image-registry.openshift-image-registry.svc:5000\/openshift\//registry-proxy.engineering.redhat.com\/rh-osbs\/openshift-}
	else
            echo "# Error: We only support registry-proxy.engineering.redhat.com as Source_Registry now "
            exit 1
	fi

	image_url_sha256_trimed=${image_url%@sha256:*}
	image_url_tag_trimed=${image_url_sha256_trimed%:v*}
        image_url_suffix_trimed=$image_url_tag_trimed
	dest_image_without_tag=${image_url_suffix_trimed/image-registry.openshift-image-registry.svc:5000/${Dest_Registry}}

        gen_image_map_accurate_tag $source_image $dest_image_without_tag
    done
    for image_name in $Static_Images; do
        gen_static_images_map $image_name
    done
}


function get_dest_registry()
{
     echo "# Enable external router for regsitry"
     Dest_Registry=$(oc get images.config.openshift.io/cluster  -o jsonpath={.status.externalRegistryHostnames[0]})
     n=0
     until [ $n -ge 20 ]
     do
        if [[ X"$Dest_Registry" != X"" ]]; then
            break
        fi
        oc patch configs.imageregistry.operator.openshift.io cluster -p '{"spec":{"defaultRoute":true}}' --type='merge' -n openshift-image-registry
        Dest_Registry=$(oc get images.config.openshift.io/cluster  -o jsonpath={.status.externalRegistryHostnames[0]})

        echo "try the $n time"
        n=$[$n+1]
        sleep 1
     done
}

function parepare_docker_config()
{
    local int_registry_user="registry"
    local registry_name=$(oc get sa $int_registry_user -o name || echo "none")
    if [[ $registry_name == "none" ]]; then
        oc create serviceaccount $int_registry_user
    fi
    oc adm policy add-cluster-role-to-user admin -z $int_registry_user

    int_registry_token=$(oc sa get-token $int_registry_user)

    if [[ X"$int_registry_token" == X"" ]]; then
        echo "# Error: No token"
        exit 1
    fi

    echo "# Create Docker Auth"
    auth_base64=$(echo -n "${int_registry_user}:${int_registry_token}"|base64 -w 0)
    cat <<EOF > $Docker_Config_File 
{ "auths": { "${Dest_Registry}": { "auth": "${auth_base64}" } } }
EOF

}

###########################Main##########################################
if [[ ! -f $Source_ImageList ]]; then
    echo "# Error: Couldn't find the file $Source_ImageList, please add image list to this file at first"
    exit 1
fi

get_dest_registry
parepare_docker_config
gen_image_map
sync_images
