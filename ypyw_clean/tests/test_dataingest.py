import pandas as pd

from dataingest import clean_headers, build_archive_path


def test_clean_headers_strips_surrounding_whitespace():
    df = pd.DataFrame({"  Name ": [1], "Amount\t": [2], " Lead Source ": [3]})

    cleaned = clean_headers(df)

    assert list(cleaned.columns) == ["Name", "Amount", "Lead Source"]


def test_build_archive_path_no_collision():
    destination = build_archive_path(
        "processed",
        "estimates.csv",
        exists_fn=lambda path: False,
        timestamp_fn=lambda: 999,
    )

    import os

    assert destination == os.path.join("processed", "estimates.csv")


def test_build_archive_path_collision_uses_timestamp_prefix():
    destination = build_archive_path(
        "processed",
        "estimates.csv",
        exists_fn=lambda path: True,
        timestamp_fn=lambda: 12345,
    )

    import os

    assert destination == os.path.join("processed", "12345_estimates.csv")
