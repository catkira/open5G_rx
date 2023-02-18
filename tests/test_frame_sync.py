import numpy as np
import os
import pytest
import logging
import os
import scipy
import matplotlib.pyplot as plt

import cocotb
import cocotb_test.simulator
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

import py3gpp
import sigmf

CLK_PERIOD_NS = 260416
CLK_PERIOD_S = CLK_PERIOD_NS * 1e-12
tests_dir = os.path.abspath(os.path.dirname(__file__))
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', 'hdl'))

class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.IN_DW = int(dut.IN_DW.value)

        self.log = logging.getLogger('cocotb.tb')
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(self.dut.clk_i, CLK_PERIOD_NS, units='ns').start())

    async def cycle_reset(self):
        self.dut.s_axis_in_tvalid.value = 0
        self.dut.reset_ni.setimmediatevalue(1)
        await RisingEdge(self.dut.clk_i)
        self.dut.reset_ni.value = 0
        await RisingEdge(self.dut.clk_i)
        self.dut.reset_ni.value = 1
        await RisingEdge(self.dut.clk_i)

@cocotb.test()
async def stream_tb(dut):
    tb = TB(dut)
    await tb.cycle_reset()

    handle = sigmf.sigmffile.fromfile(tests_dir + '/30720KSPS_dl_signal.sigmf-data')
    waveform = handle.read_samples()
    waveform /= max(waveform.real.max(), waveform.imag.max())
    waveform = scipy.signal.decimate(waveform, 16//2, ftype='fir')
    waveform /= max(waveform.real.max(), waveform.imag.max())
    waveform *= 2 ** (tb.IN_DW // 2 - 1)
    waveform = waveform.real.astype(int) + 1j*waveform.imag.astype(int)

    CP1_LEN = 20
    CP2_LEN = 18
    FFT_LEN = 256
    L_MAX = 4 # 4 SSBs
    SSB_pattern = [2, 8, 16, 22]  # case A

    START_POS = 842  #+ int(3.84e6 * 0.001 * int(ibar_SSB / 2)) + 1646 * (ibar_SSB % 2)   # this hack works for ibar_SSB = 0 .. 3
    SSB_POS = [842, 842 + int(3.84e6 * 0.02)]
    START_SYMBOL = 2
    num_symbols = 50
    symbol = np.empty((num_symbols,256), 'complex')

    pos = START_POS
    _, axs = plt.subplots(8, 7, sharex=True, sharey=True)
    axs = np.ravel(axs)
    for i in range(num_symbols):
        new_symbol = np.fft.fftshift(np.fft.fft(waveform[pos:][:FFT_LEN]))
        if (i+4)%7 == 0:
            pos += CP1_LEN + FFT_LEN
        else:
            pos += CP2_LEN + FFT_LEN
        axs[i].plot(new_symbol.real, new_symbol.imag, '.r')
        symbol[i] = new_symbol
    # plt.show()

    symbol /= max(symbol.real.max(), symbol.imag.max())
    symbol *= (2 ** (tb.IN_DW // 2 - 1) - 1)
    symbol = symbol.real.astype(int) + 1j*symbol.imag.astype(int)

    max_clk_cnt = int(3.84e6 * 0.025)  # 25ms
    clk_cnt = 0
    symbol_id = 0
    SC_cnt = 0
    pos = 0
    current_CP_len = CP2_LEN
    ibar_SSB_DEALAY = 1000
    while clk_cnt < max_clk_cnt:
        await RisingEdge(dut.clk_i)

        if pos in SSB_POS:
            dut.N_id_2_valid_i.value = 1
            # assume SSB arrives at symbol 3
            current_CP_len = CP2_LEN
            SC_cnt = 0
            symbol_id = START_SYMBOL + 1 # +1 because PSS is not included
            print(f'sending SSB at pos = {pos}')
        else:
            dut.N_id_2_valid_i.value = 0

        if pos == ibar_SSB_DEALAY:
            dut.ibar_SSB_i.value = 0
            dut.ibar_SSB_valid_i.value = 1
        else:
            dut.ibar_SSB_valid_i = 0

        data = (((int(waveform[pos].imag)  & ((2 ** (tb.IN_DW // 2)) - 1)) << (tb.IN_DW // 2)) \
            + ((int(waveform[pos].real)) & ((2 ** (tb.IN_DW // 2)) - 1)))
        dut.s_axis_in_tdata.value = data
        dut.s_axis_in_tvalid.value = 1

        if SC_cnt == (256 + current_CP_len):
            symbol_id += 1
            symbol_id %= 14
            SC_cnt = 0
            if symbol_id in [0, 7]:
                current_CP_len = CP1_LEN
            else:
                current_CP_len = CP2_LEN
            print(f'send symbol {symbol_id}')
        else:
            SC_cnt += 1

        if pos == SSB_POS[1] + 2:
            assert dut.PBCH_start_o.value == 1

        if dut.symbol_start_o.value == 1:
            print('symbol_start')
        if dut.PBCH_start_o.value == 1:
            print(f'PBCH_start at pos = {pos}')
        clk_cnt += 1
        pos += 1
    print(f'finished after {clk_cnt} clk cycles')


@pytest.mark.parametrize("IN_DW", [32])
def test_stream(IN_DW):
    dut = 'frame_sync'
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f'{dut}.sv')
    ]
    includes = []
    parameters = {}
    parameters['IN_DW'] = IN_DW
    parameters_dirname = parameters.copy()

    sim_build='sim_build/test_stream' + '_'.join(('{}={}'.format(*i) for i in parameters_dirname.items()))

    os.environ['SIM'] = 'verilator'
    if os.environ['SIM'] == 'verilator':
        cocotb_test.simulator.run(
            python_search=[tests_dir],
            verilog_sources=verilog_sources,
            includes=includes,
            toplevel=toplevel,
            module=module,
            parameters=parameters,
            sim_build=sim_build,
            testcase='stream_tb',
            force_compile=True,
            compile_args = ['-Wno-fatal']
        )
    else:
        cocotb_test.simulator.run(
            python_search=[tests_dir],
            verilog_sources=verilog_sources,
            includes=includes,
            toplevel=toplevel,
            module=module,
            parameters=parameters,
            sim_build=sim_build,
            testcase='stream_tb',
            force_compile=True
        )

if __name__ == '__main__':
    test_stream(IN_DW = 32)
