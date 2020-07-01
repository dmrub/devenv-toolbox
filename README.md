# devenv-toolbox
Development Environment Toolbox

## run-in-toolbox.sh

```
Usage: ./run-in-toolbox.sh [<options-1>] [command] [<options-2>] [<command-args>]

If no arguments provided /bin/sh is started in interactive mode.
Storage is mounted to /mnt directory.

commands:
    start                      Start container
    stop                       Stop container
    exec                       Execute command in container, this command is used by default
    build                      Build container
    install <directory>
                               Install run-in-toolbox script to the specified directory

options-1 and 2:
    -h, --help                 Display this help and exit
    -v, --verbose              Verbose output
    -c, --config=CONFIG_FILE   Path to configuration file

options-2:
    --                         End of options

current user-defined configuration:

docker.imageName = devenv-toolbox
docker.containerName = devenv-toolbox
docker.containerMountDir = /mnt
docker.appUser = toolbox
docker.appGroup = toolbox
docker.appUid = 1000
docker.appGid = 1000
docker.appHome = /mnt
docker.execArgs = ( /usr/local/bin/run-shell.sh )
docker.runArgs = (  )
docker.containerArgs = (  )
docker.buildArgs = (  )
docker.volumeDir = /home/rubinste/Kubernetes/devenv-toolbox
docker.file = Dockerfile
```

## Use tensorflow-2.2.0-jupyter / tensorflow-2.2.0-gpu-jupyter image

If you want to use Tensorflow with GPU you must have nvidia-docker2 installed:
https://github.com/NVIDIA/nvidia-docker/wiki/Installation-(version-2.0)

```
# Install Toolbox script into the new directory
mkdir tensorflow-test
./run-in-toolbox.sh install tensorflow-test
# Copy configuration file for GPU
cp config-examples/tensorflow-2.2.0-gpu-jupyter.ini tensorflow-test/toolbox-config.ini
# Or copy configuration file for CPU
cp config-examples/tensorflow-2.2.0-jupyter.ini tensorflow-test/toolbox-config.ini
# Build toolbox image
cd tensorflow-test
./run-in-toolbox.sh build
# Start image
./run-in-toolbox.sh start
# Grep Docker container protocols to find the URI of the Jupyter notebook server
./run-in-toolbox.sh logs 2>&1 | grep 'http://127.0.0.1:8888'
# To get to the container shell, use
./run-in-toolbox.sh
# You can install new software with sudo apt-get install
```
