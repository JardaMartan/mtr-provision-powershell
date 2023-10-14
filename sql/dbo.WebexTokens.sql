CREATE TABLE [dbo].[WebexTokens] (
    [Id]             INT          NOT NULL IDENTITY(1,1) PRIMARY KEY,
    [clientId]       VARCHAR (MAX) NOT NULL,
    [accessToken]    VARCHAR (MAX) NOT NULL,
    [expires]        VARCHAR (50) NOT NULL,
    [refreshToken]   VARCHAR (MAX) NOT NULL,
    [refreshExpires] VARCHAR (50) NOT NULL,
    PRIMARY KEY CLUSTERED ([Id] ASC)
);

