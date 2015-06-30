if exists (select 1
          from sysobjects
          where  id = object_id('spGK_PM_GetObjectIDFromCPR')
          and type in ('P','PC'))
   drop procedure spGK_PM_GetObjectIDFromCPR
go

CREATE PROCEDURE spGK_PM_GetObjectIDFromCPR
    @context            VARCHAR(1020),
    @cprNo              VARCHAR(10),
    @objectOwnerID      uniqueidentifier,
    @objectID           uniqueidentifier    OUTPUT,
    @aux                VARCHAR(1020)       OUTPUT
AS
BEGIN TRY
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    DECLARE @RowCnt                     INTEGER
    DECLARE @ErrNo                      INTEGER
    
    DECLARE @RetVal                     INTEGER
    SELECT  @RetVal         = -1
    
    DECLARE @ErrorSeverity              INTEGER
    SELECT  @ErrorSeverity  = 16
    DECLARE @ErrorState                 INTEGER    

    DECLARE @birthdate                  DATETIME
    DECLARE @gender                     INTEGER
    
    DECLARE @objectOwnerNamespace       VARCHAR(510)
    
    DECLARE @encryptedCprNo             VARBINARY(90)
    
    -- ---
    
    EXEC spGK_PM_PrepareSPInvocation @context OUTPUT, spGK_PM_GetObjectIDFromCPR, @cprNo
                    
    -- Prepare parameters
    SET @ObjectID = NULL
    SET @aux = ''
    
    -- Validate CPR (and extract birtdate and gender)
    EXEC spGK_CORE_ValidateCPR @cprNo, @birthdate OUTPUT, @gender OUTPUT, @aux OUTPUT

    -- gender param is negative on validation errors
    IF @gender < 0 GOTO ErrExit
    
    -- Open key to be used for encrypting CPR
    SET @RetVal = -2
    OPEN SYMMETRIC KEY CprNoEncryptKey DECRYPTION BY CERTIFICATE CertForEncryptOfCprNoKey;

    -- Get the object ID that correspond to the specified CPR (iff any). @ObjectID is NULL if no match is found.
    SET @RetVal = -3
    SELECT  @ObjectID = pm.ObjectID
    FROM    T_PM_CPR cpr, T_PM_PersonMaster pm
    WHERE   cpr.cprNo = @cprNo
    AND     cpr.personMasterID = pm.objectID
    
    IF @ObjectID IS NULL
    BEGIN
        -- No CPR entry was found
        
        SET @RetVal = -4
        
        -- If object owner ID is NULL (unspecified) - get the owner ID for the self namespace configured for this installation
        IF @objectOwnerID IS NULL
        BEGIN
            SET @RetVal = -5
            SET @aux = 'ObjectOwner ID was not specified in call, and NO default namespace (namespace-self) was defined in the config table (T_CORE_Config). Verify that DB has been initalized (spGK_InitDB).'
            SET @objectOwnerNamespace = dbo.fnGK_CORE_GetConfigValue('namespace-self')
            
            IF LEN(@objectOwnerNamespace) = 0 GOTO ErrExit
            
            SET @RetVal = -6
            EXEC spGK_PM_GetOwnerIDFromNamespace @context, @objectOwnerID OUTPUT, @objectOwnerNamespace, @aux OUTPUT
        END
        
        -- Create new entry in PersonMaster table
        SET @ObjectID = newid()
        
        SET @RetVal = -7
        
        BEGIN TRAN
            INSERT INTO T_PM_PersonMaster VALUES (@ObjectID, @objectOwnerID, GETDATE())
            INSERT INTO T_PM_CPR VALUES (EncryptByKey(key_GUID('CprNoEncryptKey'), @cprNo), @birthdate, @gender, @ObjectID, GETDATE(), @cprNo, 1)
        COMMIT TRAN
    END
    
LifeIsGood:
    SELECT  @aux = '',
            @RetVal = 0
        
ErrExit:
    IF @RetVal < 0
    BEGIN
        SELECT  @aux = 'Retrieval of object ID FROM CPR failed! ' + @aux,
                @ErrorState = @RetVal * -1
        RAISERROR (@aux, @ErrorSeverity, @ErrorState)
    END

    RETURN @RetVal
END TRY

BEGIN CATCH
    IF @@trancount > 0 ROLLBACK TRANSACTION
    
    EXEC spGK_CORE_ErrorHandler @context
    
    RETURN @RetVal
END CATCH

go

