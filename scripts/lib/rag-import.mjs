import {readFile,stat} from "node:fs/promises";
import {basename,extname} from "node:path";
import {createHash} from "node:crypto";

export function splitDocument(text){
 if(typeof text!=="string"||text.length>2000000||text.replace(/\s/g,"").length<30)throw new Error("Document vide, trop court, trop volumineux ou sans texte exploitable (OCR nécessaire pour un scan).");
 const chunks=[];
 let section="Document";
 for(const block of text.replace(/\r\n/g,"\n").split(/\n\s*\n/)){
  const value=block.trim();if(!value)continue;
  if(/^#{1,6} /.test(value)&&!value.includes("\n")){section=value.replace(/^#+\s*/,"").slice(0,160);continue;}
  for(let offset=0;offset<value.length;){
   let end=Math.min(value.length,offset+900);
   if(end<value.length){const space=value.lastIndexOf(" ",end);if(space>offset+500)end=space;}
   chunks.push({section,content:value.slice(offset,end).trim()});
   if(end===value.length)break;
   offset=Math.max(offset+1,end-100);
  }
 }
 if(!chunks.length||chunks.length>2500)throw new Error("Nombre de passages documentaire invalide.");
 return chunks;
}

export async function readDocument(file){
 if((await stat(file)).size>10*1024*1024)throw new Error("Document limité à 10 Mo.");
 const extension=extname(file).toLowerCase();
 const data=await readFile(file);
 if(![".pdf",".md",".txt"].includes(extension))throw new Error("Formats acceptés : .md, .txt et .pdf avec texte.");
 let text;
 if(extension===".pdf"){
  const {PDFParse}=await import("pdf-parse");
  const parser=new PDFParse({data:new Uint8Array(data)});
  try{
   const parsed=await parser.getText();
   if(parsed.pages.map(page=>page.text).join("").replace(/\s/g,"").length<30)throw new Error("PDF sans texte exploitable : effectuer un OCR avant l'import.");
   // Page markers preserve a useful reference in each chunk.
   text=parsed.pages.map(page=>"## Page "+page.num+"\n\n"+page.text).join("\n\n");
  }finally{await parser.destroy();}
 }else text=data.toString("utf8");
 if(text.includes("\u0000"))throw new Error("Le document doit être un texte UTF-8.");
 return {sourcePath:basename(file),hash:createHash("sha256").update(data).digest("hex"),chunks:splitDocument(text)};
}

export async function importDocument(client,{file,slug,title,version,types}){
 if(!/^[a-z0-9][a-z0-9-]{1,59}$/.test(slug||"")||!/^[-a-zA-Z0-9.]{1,30}$/.test(version||"")||!title?.trim()||title.length>180)throw new Error("Indiquer un slug stable, un titre et une version valides.");
 if(!Array.isArray(types)||!types.length||types.some(type=>!["leave","remote_work","equipment","training"].includes(type)))throw new Error("Indiquer au moins un type RH valide.");
 const document=await readDocument(file);
 const {data,error}=await client.rpc("import_hr_knowledge",{p_slug:slug,p_title:title.trim(),p_version:version,p_types:[...new Set(types)].sort(),p_source_path:document.sourcePath,p_sha256:document.hash,p_chunks:document.chunks});
 if(error)throw new Error("Import refusé : "+error.message);
 return data;
}
