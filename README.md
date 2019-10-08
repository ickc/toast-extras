# toast-extras

Stuffs related to toast

# Notes

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
