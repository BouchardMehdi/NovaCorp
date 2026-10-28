import Link from "next/link";

export const pageSize=5;
export function requestedPage(value:unknown) {
 const page=typeof value==="string"?Number(value):1;
 return Number.isSafeInteger(page)&&page>0&&page<=10000?page:1;
}
export function lastPage(total:number){return Math.max(1,Math.ceil(total/pageSize));}

export default function Pagination({page,total,pathname,params={},pageKey="page",label="Pagination"}:{page:number;total:number;pathname:string;params?:Record<string,string>;pageKey?:string;label?:string}) {
 const pages=lastPage(total);
 const url=(number:number)=>pathname+"?"+new URLSearchParams({...params,[pageKey]:String(number)});
 const numbers=Array.from(new Set([1,page-1,page,page+1,pages])).filter(number=>number>=1&&number<=pages).sort((a,b)=>a-b);
 return <nav className="pagination" aria-label={label}>
  <p className="hint">{total?`${(page-1)*pageSize+1}–${Math.min(page*pageSize,total)} sur ${total}`:"0 résultat"} · Page {page} sur {pages}</p>
  <div className="pagination-links">
   {page>1?<Link className="button secondary" href={url(page-1)} scroll={false} aria-label="Page précédente">←</Link>:<span className="button secondary" aria-disabled="true" aria-label="Page précédente">←</span>}
   {numbers.map((number,index)=><span className="page-number" key={number}>{index>0&&number>numbers[index-1]+1&&<span className="page-gap">…</span>}<Link className="button secondary" href={url(number)} scroll={false} aria-label={"Page "+number} aria-current={page===number?"page":undefined}>{number}</Link></span>)}
   {page<pages?<Link className="button secondary" href={url(page+1)} scroll={false} aria-label="Page suivante">→</Link>:<span className="button secondary" aria-disabled="true" aria-label="Page suivante">→</span>}
  </div>
 </nav>;
}
