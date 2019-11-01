# toast-extras

Stuffs related to toast

# Loading TOAST in JupyterLab

## GNU

```bash
# in /scratch/local/toast-gnu/compile/bin/run_kernel.sh
#!/bin/bash
conda activate /scratch/local/toast-gnu/conda

export LD_LIBRARY_PATH="/scratch/local/toast-gnu/compile/lib:$LD_LIBRARY_PATH"
export PYTHONPATH="/scratch/local/toast-gnu/compile/lib/python3.7/site-packages:$PYTHONPATH"
export PATH="$PATH:/scratch/local/toast-gnu/conda/bin"

exec /scratch/local/toast-gnu/conda/bin/python -m ipykernel_launcher -f "$1"
```

```json
# in ~/.local/share/jupyter/kernels/toast-gnu/kernel.json
{
 "argv": [
  "/scratch/local/toast-gnu/compile/bin/run_kernel.sh",
  "{connection_file}"
 ],
 "display_name": "toast-gnu",
 "language": "python"
}
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
