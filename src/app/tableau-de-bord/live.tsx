"use client";
import {useEffect} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase/client";
export default function Live({id,supervision=false}:{id?:string;supervision?:boolean}){
 const router=useRouter();
 useEffect(()=>{
 const client=createClient();let timer:ReturnType<typeof setTimeout>|undefined;
 const refresh=()=>{clearTimeout(timer);timer=setTimeout(()=>router.refresh(),300);};
 const channel=client.channel("hr-"+(id||"dashboard"));
 for(const table of (supervision?["requests","request_events","approval_steps","notifications"]:["requests","request_events","approval_steps"]))channel.on("postgres_changes",{event:"*",schema:"public",table,...(id?{filter:(table==="requests"?"id":"request_id")+"=eq."+id}:{})},refresh);
 channel.subscribe();window.addEventListener("focus",refresh);
 const fallback=setInterval(()=>{if(document.visibilityState==="visible")refresh();},10000);
 return()=>{clearInterval(fallback);clearTimeout(timer);window.removeEventListener("focus",refresh);void client.removeChannel(channel);};
 },[id,supervision,router]);return null;
}
