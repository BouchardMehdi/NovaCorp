import type {Json} from "@/types/database";

export type RagPassage={source_id:string;title:string;version:string;section:string;content:string;source_path:string};
export function reviewSources(value:Json|null):{passages:RagPassage[];citations:string[]}|null{
 if(!value||typeof value!=="object"||Array.isArray(value)||value.method!=="postgres_fts_fr_v1"||!Array.isArray(value.passages))return null;
 const passages=value.passages.filter((p):p is Record<string,Json>=>!!p&&typeof p==="object"&&!Array.isArray(p))
  .filter(p=>["source_id","title","version","section","content","source_path"].every(key=>typeof p[key]==="string")) as RagPassage[];
 const citations=Array.isArray(value.citations)?value.citations.filter((id):id is string=>typeof id==="string"):[];
 return {passages,citations};
}
