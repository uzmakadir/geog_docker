#!/bin/bash
  
# get Dockerfile and pull info for postBuild etc
# to inherit from https://raw.githubusercontent.com/jgomezdans/geog_docker/master/


here=$(pwd)
cmddir=$(dirname $0)
base='https://raw.githubusercontent.com/jgomezdans/geog_docker/master/'
NB_USER="${USER}"

# generate tmp dir to work in
tmp="${HOME}/tmp.$$"
rm -rf "${tmp}"
mkdir -p "${tmp}"
pushd "${tmp}"

# carry the python filter with us
cat << EOF > filter.py
#!/usr/bin/env python
l=[j for j in [i.split('#')[0].split() for i in open('Dockerfile','r').read().replace("fix-permissions","chown -R ${USER} ").replace('\\\\\n','').split('\n')] if len(j)];

for i,m in enumerate(l):
  if(m[0] == 'RUN'):
    # insert this alias in case its used
    # m[0] = 'alias fix-permissions="chown -R ${USER} " && '
    cmd = "bash -c " + "'" + ' '.join(m[1:]) + "'"
  elif (m[0] == 'ARG' or m[0] == 'ENV'):
    cmd = "export " + ' '.join(m[1:])
  elif(m[0] == 'COPY'):
    cmd = "cp " + ' '.join(m[1:])
  else:
    cmd=''
  print(cmd)
EOF


# base the install on this
wget ${base}/Dockerfile
export CONDA_DIR=$(dirname $(dirname $(which conda)))

if [[ ! -d "$CONDA_DIR" ]]
then
  unset CONDA_DIR
fi

# check we have it
if [ -z "$CONDA_DIR" ]
then
      echo "${0}: ENV ERROR"
      echo 'ERROR: Cannot find $CONDA_DIR:'
      echo 'which conda returns:'
            which conda
      echo 'from both conda run env and env'
      echo '    - Check you have anacondsa or miniconda installed'
      echo '      and put the dist in CONDA_DIR'
      exit 1
fi

echo "CONDA_DIR: $CONDA_DIR"
#${SUDO} chown -R ${USER} .

# filter Dockerfile
echo '#!/bin/bash' > conda.recipe
echo "export PATH=\"${CONDA_DIR}/bin:${PATH}\""
echo "which conda" >> conda.recipe
echo 'alias fix-permissions="chown -R ${USER} "' >> conda.recipe

# unset the env to start with
conda_env=$(grep conda_env Dockerfile | grep ARG | cut -d '=' -f 2)
echo "conda deactivate && conda env remove --prefix ${conda_env}" >> conda.recipe

# take the enviro=nment with us
echo "export CONDA_DIR=${CONDA_DIR}" >> conda.recipe
python filter.py >> conda.recipe
chmod +x conda.recipe

# get this rather than try to mimic the COPY
wget ${base}/environment.yml

# so as not to mess up
mkdir -p notebooks
wget ${base}/notebooks/00-Test_Notebook.ipynb
mv *.ipynb notebooks

# set a debug break point here
if [ ! -z "$DEBUG" ]
then
  pwd
  exit 0
fi

${SUDO} ./conda.recipe 2| tee conda.recipe.$$.log

if [ $? -eq 0 ]; then
   echo OK
else
   echo "${0} FAILED with code $?"
   echo "see log in ${CWD}/conda.recipe.$$.log"
   exit 1
fi

# so they can carry through
grep ENV < Dockerfile | sed 's/ENV /export /' > ${HOME}/.dockenvrc

grep -v dockenvrc <  ~/.bashrc > ~/.bashrc.bak
echo 'source ~/.dockenvrc' >> ~/.bashrc.bak
mv ~/.bashrc.bak ~/.bashrc

popd
# tidy
rm -rf ${tmp} ${HOME}/tmp

