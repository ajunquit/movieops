namespace MovieOps.Application.Exceptions;

public class TmdbUnavailableException(string message, Exception? innerException = null)
    : Exception(message, innerException);
