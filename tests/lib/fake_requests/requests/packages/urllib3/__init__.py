import warnings


def disable_warnings(category=Warning):
    warnings.simplefilter("ignore", category)
