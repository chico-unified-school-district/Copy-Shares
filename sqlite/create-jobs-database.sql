CREATE TABLE "jobs" (
	"id"	INTEGER,
	"srcServer"	TEXT,
	"srcShare"	TEXT,
	"dstServer"	TEXT,
	"dstShare"	TEXT,
	"excludeFiles"	TEXT,
	"excludeDirs"	TEXT,
	"executeJob"	TEXT,
	CONSTRAINT "id" PRIMARY KEY("id")
)