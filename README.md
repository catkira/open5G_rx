[![Verify](https://github.com/catkira/5G_SSB_sync/actions/workflows/verify.yml/badge.svg)](https://github.com/catkira/5G_SSB_sync/actions/workflows/verify.yml)

# 5G_SSB_sync
HDL code for 5G SSB synchronization.<br>
Implemented so far:<br>
* PSS correlator

TODO:
* optimized PSS correlator like described here: https://ieeexplore.ieee.org/document/8641097
* peak detector
* SSS detector
* channel estimator
* SSB demodulator

# Tests
```
  sudo apt install iverilog
  pip install -e requirements.txt
  git clone https://github.com/catkira/cocotb.git
  cd cocotb && pip install -e . && cd ..
  pytest --workers 8
```


