// n8n 2.42.5 CLI sets activeVersionId but does not update the separate published
// mapping read by Execute Sub-workflow. Keep both records aligned for these IDs.
// Run after publish:workflow, then restart the server to clear its runtime cache.
export const publicationSyncCode=`
const {DatabaseSync}=require('node:sqlite');
const db=new DatabaseSync('/home/node/.n8n/database.sqlite');
try{
 db.exec('PRAGMA foreign_keys=ON; PRAGMA busy_timeout=10000; BEGIN;');
 for(const id of publicationIds){
  const row=db.prepare('select activeVersionId from workflow_entity where id=? and isArchived=0').get(id);
  if(!row?.activeVersionId||!db.prepare('select versionId from workflow_history where workflowId=? and versionId=?').get(id,row.activeVersionId))throw new Error('Published version unavailable');
  db.prepare("insert into workflow_published_version(workflowId,publishedVersionId) values(?,?) on conflict(workflowId) do update set publishedVersionId=excluded.publishedVersionId,updatedAt=STRFTIME('%Y-%m-%d %H:%M:%f','NOW')").run(id,row.activeVersionId);
 }
 db.exec('COMMIT;');
}catch(e){try{db.exec('ROLLBACK;');}catch{}throw e;}
finally{db.close();}
`;
