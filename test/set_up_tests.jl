using Aqua
using Dates
using Onda
using OndaVision
using PyMNE
using PythonCall
using Suppressor
using Test
using TimeSpans
using UUIDs

const DATA_DIR = joinpath(@__DIR__, "data")
vhdr(name) = joinpath(DATA_DIR, name)

const _VMRK_FILE = joinpath(DATA_DIR, "test.vmrk")
const _VHDR_FILE = joinpath(DATA_DIR, "test_highpass.vhdr")
const _SAMPLE_RATE = 1000.0  # Hz (SamplingInterval=1000 µs)

const _warnings = PythonCall.pynew()
PythonCall.pycopy!(_warnings, pyimport("warnings"))

# Load a file via MNE-Python and return data as a (n_channels × n_samples) Matrix{Float64}
# in µV (MNE stores data internally in V; we rescale to µV for comparison).
function _mne_load(vhdr_path)
    _warnings.filterwarnings("ignore")
    raw = PyMNE.io.read_raw_brainvision(vhdr_path; preload=true, verbose=false)
    _warnings.resetwarnings()
    data = pyconvert(Matrix{Float64}, raw.get_data())
    return data .* 1e6
end
