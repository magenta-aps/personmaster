-- Create new column
IF NOT EXISTS (SELECT * FROM sys.tables t INNER JOIN sys.columns c on t.object_id = c.object_id AND t.name = 'T_PM_CPR' AND c.name = 'inCprBroker')
	ALTER TABLE T_PM_CPR Add inCprBroker BIT