import {readFile} from "node:fs/promises";
import {container,inside} from "./n8n-tools.mjs";
try{
 const workflows=await Promise.all(["approvals","notifications"].map(async name=>JSON.parse(await readFile("n8n/workflows/"+name+".json","utf8"))));
 const result=inside(container(),`
 const fs=require("node:fs"),os=require("node:os"),path=require("node:path"),cp=require("node:child_process");
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),"novacorp-workflows-"));
 try{
  const file=path.join(dir,"workflows.json");fs.writeFileSync(file,fs.readFileSync(0),{mode:0o600});
  cp.execFileSync("n8n",["import:workflow","--input",file],{stdio:"pipe"});
  console.log("Deux workflows importés. Publier avec npm run n8n:approvals:start.");
 }catch{console.error("Import des workflows impossible.");process.exitCode=1;}
 finally{fs.rmSync(dir,{recursive:true,force:true});}
 `,JSON.stringify(workflows));
 console.log(result.trim());
}catch{console.error("Import impossible. Démarrez n8n et configurez ses connexions locales.");process.exitCode=1;}
