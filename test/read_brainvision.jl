raw = PyMNE.io.read_raw_brainvision(joinpath(@__DIR__, "data", "test.vhdr"))
Matrix(raw.get_data())
