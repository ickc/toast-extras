# toast-extras

Stuffs related to toast

# Loading TOAST

Adapt these to your environment,

- prefix to TOAST
- `python3.10`

## GNU

```bash
# in /opt/cmb/toast-gnu/compile/bin/run_kernel.sh
#!/bin/bash
conda activate /opt/cmb/toast-gnu/conda

export LD_LIBRARY_PATH="/opt/cmb/toast-gnu/compile/lib:$LD_LIBRARY_PATH"
export PYTHONPATH="/opt/cmb/toast-gnu/compile/lib/python3.10/site-packages:$PYTHONPATH"
export PATH="/opt/cmb/toast-gnu/compile/bin:/opt/cmb/toast-gnu/conda/bin:$PATH"

exec /opt/cmb/toast-gnu/conda/bin/python -m ipykernel_launcher -f "$1"
```

```json
# in ~/.local/share/jupyter/kernels/toast-gnu/kernel.json
{
 "argv": [
  "/opt/cmb/toast-gnu/compile/bin/run_kernel.sh",
  "{connection_file}"
 ],
 "display_name": "toast-gnu",
 "language": "python"
}
```

To use it with vscode, (see <https://code.visualstudio.com/docs/python/environments#_environment-variable-definitions-file>)

```sh
# ${workspaceFolder}/.env
LD_LIBRARY_PATH=/opt/cmb/toast-gnu/compile/lib:${LD_LIBRARY_PATH}
PYTHONPATH=/opt/cmb/toast-gnu/compile/lib/python3.10/site-packages:${PYTHONPATH}
PATH=/opt/cmb/toast-gnu/compile/bin:/opt/cmb/toast-gnu/conda/bin:${PATH}
```

## Intel

Loading TOAST correctly in JupyterLab, you may need to do

```bash
# in /scratch/local/toast-intel-fftw/bin/run_kernel.sh
#!/bin/bash

. activate "$SCRATCH/local/toast-intel-fftw"
. /opt/intel/bin/compilervars.sh -arch intel64
exec /scratch/local/toast-intel-fftw/bin/python -m ipykernel_launcher -f "$1"
```

```json
# in ~/.local/share/jupyter/kernels/toast-intel-fftw/kernel.json
{
 "argv": [
  "/scratch/local/toast-intel-fftw/bin/run_kernel.sh",
  "{connection_file}"
 ],
 "display_name": "toast-intel-fftw",
 "language": "python"
}
```
