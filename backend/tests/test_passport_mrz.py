from backend.passport_mrz import check_digit, find

# ICAO 9303 specimen passport
L1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
L2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"


def test_check_digit():
    assert check_digit("L898902C3") == 6
    assert check_digit("740812") == 2
    assert check_digit("120415") == 9


def test_parse_specimen():
    mrz = find([L1, L2], known=None)
    assert mrz is not None
    assert mrz.surname == "ERIKSSON"
    assert mrz.passport_number == "L898902C3"
