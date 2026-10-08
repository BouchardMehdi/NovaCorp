import Link from "next/link";
import {notFound} from "next/navigation";
import {requireUser} from "@/lib/auth/session";
import {validId} from "@/lib/hr";
import RequestForm from "../../request-form";
export default async function Edit({params}:{params:Promise<{id:string}>}){
 const {id}=await params;if(!validId(id))notFound();
 const {supabase,user}=await requireUser();
 const {data}=await supabase.from("requests").select("*").eq("id",id).eq("requester_id",user.id).eq("status","draft").maybeSingle();
 if(!data)notFound();
 return <main className="dashboard-main"><Link className="back" href={"/tableau-de-bord/demandes/"+id}>← Revenir à la demande</Link><h1>Modifier le brouillon</h1><p className="intro">Complétez les informations avant de soumettre.</p><RequestForm request={data}/></main>;
}