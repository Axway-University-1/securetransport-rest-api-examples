"""The exception classes of the real requests library, with the same family tree."""


class RequestException(IOError):
    pass


class HTTPError(RequestException):
    pass


class ConnectionError(RequestException):
    pass


class Timeout(RequestException):
    pass


class ConnectTimeout(ConnectionError, Timeout):
    pass


class ReadTimeout(Timeout):
    pass
