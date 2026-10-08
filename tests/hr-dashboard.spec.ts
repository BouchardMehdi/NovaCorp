import {test,expect,type Page} from "@playwright/test";
import {createClient} from "@supabase/supabase-js";
import {randomUUID} from "node:crypto";
import {execFileSync} from "node:child_process";
const password="NovaCorpDemo2026!";
const admin=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.SUPABASE_SERVICE_ROLE_KEY!,{auth:{persistSession:false,autoRefreshToken:false}});
const employee=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{auth:{persistSession:false,autoRefreshToken:false}});
const hr=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{auth:{persistSession:false,autoRefreshToken:false}});
let userId:string,email:string,requestId:string,errorId:string;
const title="Suivi RH "+randomUUID().slice(0,8);
test.beforeAll(async()=>{
 email="dashboard-ui-"+randomUUID()+"@novacorp.test";
 const created=await admin.auth.admin.createUser({email,password,email_confirm:true});expect(created.error).toBeNull();userId=created.data.user!.id;
 const manager=(await admin.from("profiles").select("id").eq("role","manager").limit(1).single()).data!;
 expect((await admin.from("profiles").update({manager_id:manager.id}).eq("id",userId)).error).toBeNull();
 expect((await employee.auth.signInWithPassword({email,password})).error).toBeNull();
 expect((await hr.auth.signInWithPassword({email:"rh@novacorp.test",password})).error).toBeNull();
 const request=await employee.from("requests").insert({requester_id:userId,request_type:"equipment",title,amount:1501,quantity:1}).select("id").single();
 expect(request.error).toBeNull();requestId=request.data!.id;
 expect((await employee.rpc("submit_hr_request",{p_request_id:requestId})).error).toBeNull();
 const claim=await admin.rpc("claim_hr_qualification",{p_execution_id:"dashboard-ui-"+randomUUID(),p_provider:"test",p_model:"fixture",p_request_id:requestId});
 expect(claim.error).toBeNull();const lease=claim.data as {run_id:string;lease_token:string};
 expect((await admin.rpc("complete_hr_qualification",{p_run_id:lease.run_id,p_lease_token:lease.lease_token,p_result:{qualification:"eligible",summary:"Fixture supervision",response_draft:"Attente décision"}})).error).toBeNull();
 execFileSync("docker",["exec","-i","supabase_db_NovaCorp","psql","-U","supabase_admin","-d","postgres","-v","ON_ERROR_STOP=1"],{input:"begin; set local session_replication_role='replica'; update public.approval_steps set activated_at=now()-interval '49 hours',due_at=now()-interval '1 hour' where request_id='"+requestId+"' and position=1; commit;",encoding:"utf8"});
 const failure=await employee.from("requests").insert({requester_id:userId,request_type:"equipment",title:title+" erreur",amount:80,quantity:1}).select("id").single();expect(failure.error).toBeNull();errorId=failure.data!.id;
 expect((await employee.rpc("submit_hr_request",{p_request_id:errorId})).error).toBeNull();
 const failed=await admin.rpc("claim_hr_qualification",{p_execution_id:"dashboard-ui-fail-"+randomUUID(),p_provider:"test",p_model:"fixture",p_request_id:errorId});
 expect(failed.error).toBeNull();const failedLease=failed.data as {run_id:string;lease_token:string};
 expect((await admin.rpc("fail_hr_qualification",{p_run_id:failedLease.run_id,p_lease_token:failedLease.lease_token,p_error_code:"llm_http_error"})).error).toBeNull();
});
test.afterAll(async()=>{
 if(!userId)return;
 const requests=(await employee.from("requests").select("id,status").eq("requester_id",userId)).data||[];
 for(const r of requests)if(!["approved","rejected","cancelled"].includes(r.status))await employee.rpc("cancel_hr_request",{p_request_id:r.id});
 execFileSync("docker",["exec","-i","supabase_db_NovaCorp","psql","-U","supabase_admin","-d","postgres","-v","ON_ERROR_STOP=1"],{input:"begin; delete from public.requests where requester_id='"+userId+"'; delete from public.leave_balances where employee_id='"+userId+"'; commit;",encoding:"utf8"});
 expect((await admin.auth.admin.deleteUser(userId)).error).toBeNull();
});
async function login(page:Page,address:string){
 await page.goto("/connexion");await page.getByLabel("Adresse email professionnelle").fill(address);
 await page.getByLabel("Mot de passe",{exact:true}).fill(password);await page.getByRole("button",{name:"Se connecter",exact:true}).click();
 await expect(page).toHaveURL(/\/tableau-de-bord$/);
}
test("la supervision est protégée pour visiteurs, salariés et managers",async({page})=>{
 await page.goto("/tableau-de-bord/supervision");await expect(page).toHaveURL(/\/connexion$/);
 for(const address of [email,"manager@novacorp.test"]){
  await login(page,address);await expect(page.getByRole("link",{name:"Supervision RH",exact:true})).toHaveCount(0);
  await page.goto("/tableau-de-bord/supervision");await expect(page.getByRole("heading",{name:"Supervision RH",exact:true})).toHaveCount(0);
  await expect(page.getByText("404",{exact:true})).toBeVisible();
  await page.goto("/tableau-de-bord");await page.getByRole("button",{name:"Se déconnecter"}).click();
 }
});
test("les RH voient les compteurs exacts, les retards, les incidents et leurs liens",async({page})=>{
 await login(page,"rh@novacorp.test");await page.getByRole("link",{name:"Supervision RH",exact:true}).click();
 await expect(page.getByRole("heading",{name:"Supervision RH",exact:true})).toBeVisible();
 const report=(await hr.rpc("get_hr_dashboard")).data as {total:number;overdue_count:number};
 await expect(page.getByRole("region",{name:"Demandes soumises",exact:true}).locator("strong")).toHaveText(String(report.total));
 await expect(page.getByRole("region",{name:"Validations en retard",exact:true}).locator("strong")).toHaveText(String(report.overdue_count));
 const pending=page.locator("section").filter({has:page.getByRole("heading",{name:"Validations à suivre",exact:true})});
 await expect(pending.getByRole("link",{name:new RegExp(title+"$")})).toHaveAttribute("href","/tableau-de-bord/demandes/"+requestId);
 await expect(pending.getByText("En retard",{exact:true}).first()).toBeVisible();
 const incidents=page.locator("section").filter({has:page.getByRole("heading",{name:"Incidents d’automatisation et d’envoi",exact:true})});
 await expect(incidents.getByRole("link",{name:new RegExp(title+" erreur$")})).toHaveAttribute("href","/tableau-de-bord/demandes/"+errorId);
 await expect(incidents.getByText("Service de qualification indisponible",{exact:true}).first()).toBeVisible();
 await page.screenshot({path:"test-results/hr-dashboard-desktop.png",fullPage:true});
 await pending.getByRole("link",{name:new RegExp(title+"$")}).click();
 await expect(page.getByRole("heading",{name:title,exact:true})).toBeVisible();
});
test("le filtre s’applique à toute la supervision et la DRH y accède",async({page})=>{
 await login(page,"drh@novacorp.test");await page.getByRole("link",{name:"Supervision RH",exact:true}).click();
 await page.getByLabel("Type de demande").selectOption("training");await page.getByRole("button",{name:"Filtrer",exact:true}).click();
 await expect(page).toHaveURL(/type=training/);
 const report=(await hr.rpc("get_hr_dashboard",{p_request_type:"training"})).data as {total:number};
 await expect(page.getByRole("region",{name:"Demandes soumises",exact:true}).locator("strong")).toHaveText(String(report.total));
 await expect(page.getByRole("link",{name:new RegExp(title)})).toHaveCount(0);
});
test("la supervision reste utilisable sur mobile",async({page})=>{
 await page.setViewportSize({width:390,height:844});await login(page,"rh@novacorp.test");
 await page.getByRole("link",{name:"Supervision RH",exact:true}).click();
 await expect(page.getByRole("heading",{name:"Supervision RH",exact:true})).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
 await page.screenshot({path:"test-results/hr-dashboard-mobile.png",fullPage:true});
});
