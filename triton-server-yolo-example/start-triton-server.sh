################################################################################
# SPDX-FileCopyrightText: Copyright (c) 2024 Levi Pereira. All rights reserved.
# SPDX-License-Identifier: Apache 2.0
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.
################################################################################


#!/bin/bash

# Script to convert ONNX models to TensorRT engines and start NVIDIA Triton Inference Server.

# Usage:
# ./start-triton-server.sh [--models <models>] [--plugin efficientNMS/yoloNMS/none] [--opt_batch_size <number>] [--max_batch_size <number>] [--instance_group <number>] 
 

usage() {
    echo "Usage: $0 [--models <models>] [--model_mode <eval/infer>]  [--plugin efficientNMS/yoloNMS/none] [--opt_batch_size <number>] [--max_batch_size <number>] [--instance_group <number>] [--force] [--reset_all]"
    echo "  - Use --models to specify the YOLO model name. Choose one or more with comma separated. yolov9-c,yolov9-c-relu,yolov9-c-qat,yolov9-c-relu-qat,yolov9-e,yolov9-e-qat,yolov8n,yolov8s,yolov8m,yolov8l,yolov8x,yolov7,yolov7-qat,yolov7x,yolov7x-qat"
    echo "  - Use --model_mode - Model was optimized for EVALUATION and INFERENCE. Choose from 'eval' or 'infer'"
    echo "  - Use --plugin - efficientNMS , yoloNMS or none"
    echo "  - Use --opt_batch_size to specify the optimal batch size for TensorRT engines."
    echo "  - Use --max_batch_size to specify the maximum batch size for TensorRT engines."
    echo "  - Use --instance_group to specify the number of TensorRT engine instances loaded per model in the Triton Server."
    echo "  - Use --force Rebuild TensorRT engines even if they already exist."
    echo "  - Use --reset_all Purge all existing TensorRT engines and their respective configurations."
}

function check_model() {
    local model_names=("yolov9-c" "yolov9-c-relu"  "yolov9-c-qat" "yolov9-c-relu-qat" "yolov9-e" "yolov9-e-qat" "yolov8n" "yolov8s" "yolov8m" "yolov8l" "yolov8x" "yolov7" "yolov7-qat" "yolov7x" "yolov7x-qat")
    for model in "${model_names[@]}"; do
        if [[ "$1" == "$model" ]]; then
            return 0
        fi
    done
    return 1
}


# Function to find a unique directory name in models_trash
get_unique_trash_dir_name() {
    local base_name="$1"
    local i=1
    local new_dir_name="$base_name"

    while [ -d "$trash_dir/$new_dir_name" ]; do
        new_dir_name="${base_name}_${i}"
        ((i++))
    done

    echo "$new_dir_name"
}

# Function to calculate the available GPU memory
function get_free_gpu_memory() {
    # Get the total memory and used memory from nvidia-smi for GPU 0
    local total_memory=$(nvidia-smi --id=0 --query-gpu=memory.total --format=csv,noheader,nounits | awk '{print $1}')
    local used_memory=$(nvidia-smi --id=0 --query-gpu=memory.used --format=csv,noheader,nounits | awk '{print $1}')

    # Calculate free memory
    local free_memory=$((total_memory - used_memory))
    echo "$free_memory"
}

# Default values
max_batch_size=""
opt_batch_size=""
instance_group=""
trt_plugin=""
force_build=false
reset_all=false
model_mode=""
model_names=()

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi


# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --reset_all)
            reset_all=true
            break
            ;;
        --force)
            force_build=true
            shift
            ;;
        --models)
            IFS=',' read -r -a model_names <<< "$2"
            for model in "${model_names[@]}"; do
                if ! check_model "$model"; then
                    echo "Invalid model name: $model"
                    usage
                    exit 1
                fi
            done
            shift 2
            ;;
        --model_mode)
            model_mode="$2"
            if [[ "$model_mode" != "eval" && "$model_mode" != "infer" ]]; then
                echo "Invalid value for --model_mode. Choose 'eval' or 'infer'."
                exit 1
            fi
            shift 2
            ;;
        --plugin)
            trt_plugin="$2"
            if [[ "$trt_plugin" != "efficientNMS" && "$trt_plugin" != "yoloNMS" && "$trt_plugin" != "none" ]]; then
                echo "Invalid value for --plugin. Choose 'efficientNMS' or 'yoloNMS' or 'none'."
                exit 1
            fi
            shift 2
            ;;
        --opt_batch_size)
            if [[ ! "$2" =~ ^[0-9]+$ || "$2" -le 0 ]]; then
                echo "Invalid value for --opt_batch_size. Must be a positive integer."
                exit 1
            fi
            opt_batch_size="$2"
            shift 2
            ;;
        --max_batch_size)
            if [[ ! "$2" =~ ^[0-9]+$ || "$2" -le 0 ]]; then
                echo "Invalid value for --max_batch_size. Must be a positive integer."
                exit 1
            fi
            max_batch_size="$2"
            shift 2
            ;;
        --instance_group)
            if [[ ! "$2" =~ ^[0-9]+$ || "$2" -le 0 ]]; then
                echo "Invalid value for --instance_group. Must be a positive integer."
                exit 1
            fi
            instance_group="$2"
            shift 2
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

# Check if all flags are set
if [[ -z "$model_mode" || -z "$trt_plugin" || -z "$opt_batch_size" || -z "$max_batch_size" || -z "$instance_group" || ${#model_names[@]} -eq 0 ]]; then
    echo "Missing required flag(s)."
    usage
    exit 1
fi


# Check if reset_all is true
if $reset_all; then
    # Ask user for confirmation
    read -p "Are you sure you want to delete engines models files generated in ./models/? (y/n) " confirm

    # Check user's response
    if [[ $confirm == [Yy] ]]; then
        # Delete files
        rm -rf ./models/*
        echo "Model engines/configuration was reseted. Please re-run without --reset-all flag."
        exit 0
    else
        echo "Operation canceled by the user."
        exit 0
    fi
fi


# Calculate workspace size based on free GPU memory
workspace=$(get_free_gpu_memory)

# Model List
if [[ ${#model_names[@]} -eq 0 ]]; then
    model_names=("yolov9-c" "yolov9-c-relu" "yolov9-e" "yolov8n" "yolov8s" "yolov8m" "yolov8l" "yolov8x" "yolov7" "yolov7x")
fi

trash_dir="./models_trash"
mkdir -p "$trash_dir"

for model_dir in ./models/*; do
    if [ -d "$model_dir" ]; then
        # Extract model_name from the directory path
        model_name=$(basename "$model_dir")
        if [[ ! " ${model_names[@]} " =~ " $model_name " ]]; then
            echo "Model name $model_name is not in the list."
            echo "Moving directory $model_dir to models_trash."
            # Get a unique name for the trash directory
            new_trash_dir_name=$(get_unique_trash_dir_name "$model_name")
            mv "$model_dir" "$trash_dir/$new_trash_dir_name"
            echo "Directory $model_dir moved to $trash_dir/$new_trash_dir_name."
        fi
    fi
done

# Convert ONNX models to TensorRT engines
for model_name in "${model_names[@]}"; do
    if [[ $model_name == *"yolov8"* ]]; then
        if [[ $trt_plugin != "yoloNMS" ]]; then
            echo "Model '$model_name' only support --plugin yoloNMS. The efficientNMS will be supported on future."
            exit 1
        fi
    fi
    if [[ $model_name == *"qat"* ]]; then
        if [[ $trt_plugin != "efficientNMS" ]]; then
            echo "Model '$model_name' only support --plugin efficientNMS . The yoloNMS will be supported on future."
            exit 1
        fi
    fi
    if [[ $model_mode == "eval" && $trt_plugin == "none" ]]; then
        echo "Not Supported EVALUATION without efficientNMS or yoloNMS. Only INFERENCE is supported to perfomance latency testing purpose. "
        exit 1
    fi
    
    model_dir=./models/$model_name/1
    mkdir -p $model_dir

    if [[ $model_mode == "eval" || $model_mode == "infer"  && $trt_plugin != "none" ]]; then
        if [[ $trt_plugin == "efficientNMS" ]]; then
            onnx_file=./models_onnx/${model_mode}-${model_name}-end2end.onnx
            download_model=${model_mode}-${model_name}-end2end
        fi
        if [[ $trt_plugin == "yoloNMS" ]]; then
            onnx_file=./models_onnx/${model_mode}-${model_name}-trt.onnx
            download_model=${model_mode}-${model_name}-trt
        fi
        trt_file=${model_dir}/${model_mode}-${trt_plugin}-${model_name}-max-batch-${max_batch_size}.engine
        file_pattern="${model_dir}/${model_mode}-${trt_plugin}-${model_name}-max-batch-*.engine"
    fi
    

    if [[ $model_mode == "infer" && $trt_plugin == "none" ]]; then
        onnx_file=./models_onnx/infer-${model_name}.onnx
        trt_file=${model_dir}/infer-${model_name}-max-batch-${max_batch_size}.engine
        file_pattern="${model_dir}/infer-${model_name}-max-batch-*.engine"
        download_model=infer-${model_name}
    fi


    if [[ ! -f "$onnx_file" ]]; then
        cd ./models_onnx || exit 1
        bash ./download_models.sh $download_model
        cd ../ || exit 1
    fi

    if [[ ! -f "$onnx_file" ]]; then
         echo " $model_name  ONNX model file not found: $onnx_file"
         exit 1
     fi

    build_file=false
    file_count=0

    for existing_file in $file_pattern; do
        if [[ -f "$existing_file" ]]; then
            echo $existing_file
            existing_batch_size=$(echo "$existing_file" | sed -n 's/.*max-batch-\([0-9]*\).*/\1/p')
            if [[ ! "$max_batch_size" -gt "$existing_batch_size" ]]; then
                ((file_count++))
            fi
        fi
    done



    if [[ $file_count -eq 0 ]]; then
        build_file=true
    fi

    if $build_file || $force_build; then
        if [[ $model_name == *"qat"* ]]; then
            /usr/src/tensorrt/bin/trtexec \
                --onnx="$onnx_file" \
                --minShapes=images:1x3x640x640 \
                --optShapes=images:${opt_batch_size}x3x640x640 \
                --maxShapes=images:${max_batch_size}x3x640x640 \
                --fp16 \
                --int8 \
                --useCudaGraph \
                --workspace="$workspace" \
                --saveEngine="$trt_file"  
        else
            /usr/src/tensorrt/bin/trtexec \
                --onnx="$onnx_file" \
                --minShapes=images:1x3x640x640 \
                --optShapes=images:${opt_batch_size}x3x640x640 \
                --maxShapes=images:${max_batch_size}x3x640x640 \
                --fp16 \
                --useCudaGraph \
                --workspace="$workspace" \
                --saveEngine="$trt_file"  
        fi
        if [[ $? -ne 0 ]]; then
            echo "Conversion of $model_name ONNX model to TensorRT engine failed"
            exit 1
        fi
    fi
done


# Update Triton server configuration files
for model_name in "${model_names[@]}"; do
    
    model_dir=./models/$model_name/1
    

    if [[ $trt_plugin != "none" ]]; then
        model_end2end_type=""
        if [[ $trt_plugin == "efficientNMS" ]]; then
            model_end2end_type="end2end"
        fi
        if [[ $trt_plugin == "yoloNMS" ]]; then
            model_end2end_type="trt"
        fi

        if [[ $model_name == *"yolov7"* ]]; then
            model_config_template=./models_config/yolov7_onnx_${model_end2end_type}.pbtxt
        fi
        if [[ $model_name == *"yolov9"* ]]; then
            model_config_template=./models_config/yolov9_onnx_${model_end2end_type}.pbtxt
        fi
        if [[ $model_name == *"yolov8"* ]]; then
            model_config_template=./models_config/yolov8_onnx_${model_end2end_type}.pbtxt
        fi
        trt_file=${model_mode}-${trt_plugin}-${model_name}-max-batch-${max_batch_size}.engine
        file_pattern="$model_dir/${model_mode}-${trt_plugin}-${model_name}-max-batch-*.engine"
    else
        if [[ $model_name == *"yolov7"* ]]; then
            model_config_template=./models_config/yolov7_onnx.pbtxt
        fi
        if [[ $model_name == *"yolov7x"* ]]; then
            model_config_template=./models_config/yolov7x_onnx.pbtxt
        fi
        if [[ $model_name == *"yolov9"* ]]; then
            model_config_template=./models_config/yolov9_onnx.pbtxt
        fi
        if [[ $model_mode == "infer" ]]; then
            trt_file=infer-${model_name}-max-batch-${max_batch_size}.engine
            file_pattern="$model_dir/infer-${model_name}-max-batch-*.engine"
        fi
        
    fi

    config_file="./models/$model_name/config.pbtxt"

    cp "$model_config_template" "$config_file"
    if [[ $model_mode == "eval" ]]; then
        sed -i "s/TOPK/300/g" "$config_file"
        echo "Configured Topk-all 300 in $config_file"
    fi
    if [[ $model_mode == "infer" ]]; then
        sed -i "s/TOPK/100/g" "$config_file"
        echo "Configured Topk-all 100 in $config_file"
    fi

    closest_batch_size=9999
    for existing_file in $file_pattern; do
        if [[ -f "$existing_file" ]]; then
            existing_batch_size=$(echo "$existing_file" | sed -n 's/.*max-batch-\([0-9]*\).*/\1/p')

           if [[ ! "$max_batch_size" -gt "$existing_batch_size" ]]; then
                if [[ "$closest_batch_size" -gt "$existing_batch_size" ]]; then
                    closest_batch_size=$existing_batch_size
                    trt_file=$(basename "$existing_file")
                fi
            fi
        fi
    done

    sed -i "s/model_template_name/$model_name/g" "$config_file"
    sed -i "s/model_template_file/$trt_file/g" "$config_file"
    sed -i "s/max_batch_size: [0-9]*/max_batch_size: $max_batch_size/" "$config_file"
    echo "max_batch_size updated to $max_batch_size in $config_file"
    sed -i "s/count: [0-9]*/count: $instance_group/" "$config_file"
    echo "instance_group updated to $instance_group in $config_file"
done

# Start Triton Inference Server with the converted models
/opt/tritonserver/bin/tritonserver \
    --model-repository=/apps/models \
    --disable-auto-complete-config \
    --log-verbose=0
