import {createClient} from "@supabase/supabase-js";
import {readFile} from "node:fs/promises";
import {importDocument} from "./lib/rag-import.mjs";

try{
 const args=process.argv.slice(2);
 if(args.includes("--help")){
  console.log('npm run rag:import -- --file "document.pdf" --slug politique-conges --title "Politique congés" --version 1 --types leave');
  console.log("--types accepte une liste séparée par des virgules ou all. L'import réactive la version indiquée ; vérifier son contenu avant import.");
 }else{
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!url||!key||!["localhost","127.0.0.1","[::1]"].includes(new URL(url).hostname))throw new Error("Import réservé à Supabase local configuré dans .env.local.");
  const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  let documents;
  if(args.length===1&&args[0]==="--seed")documents=JSON.parse(await readFile("rag/corpus/manifest.json","utf8")).map(document=>({...document,file:"rag/corpus/"+document.file}));
  else{
   const allowed=["--file","--slug","--title","--version","--types"],options={};
   for(let index=0;index<args.length;index+=2){if(!allowed.includes(args[index])||!args[index+1]||Object.hasOwn(options,args[index]))throw new Error("Arguments invalides. Utiliser --help.");options[args[index]]=args[index+1];}
   documents=[{file:options["--file"],slug:options["--slug"],title:options["--title"],version:options["--version"],types:options["--types"]==="all"?["leave","remote_work","equipment","training"]:(options["--types"]||"").split(",")}];
  }
  for(const document of documents){const result=await importDocument(client,document);console.log("OK "+document.slug+" v"+document.version+" : "+result.chunks+" passages, "+(result.replayed?"version déjà importée":"nouvelle version")+".");}
 }
}catch(error){console.error(error.message);process.exitCode=1;}
