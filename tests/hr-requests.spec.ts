import {test,expect,type Page} from "@playwright/test";
import {createClient} from "@supabase/supabase-js";
import {randomUUID} from "node:crypto";
import {execFileSync} from "node:child_process";
const password="NovaCorpDemo2026!";
const admin=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.SUPABASE_SERVICE_ROLE_KEY!,{auth:{persistSession:false,autoRefreshToken:false}});
const client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{auth:{persistSession:false,autoRefreshToken:false}});
let userId:string,email:string;
test.beforeAll(async()=>{
 email="ui-"+randomUUID()+"@novacorp.test";
 const {data,error}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{first_name:"Test",last_name:"Interface"}});
 expect(error).toBeNull();userId=data.user!.id;
 const managerClient=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{auth:{persistSession:false,autoRefreshToken:false}});
 const manager=await managerClient.auth.signInWithPassword({email:"manager@novacorp.test",password});
 expect(manager.error).toBeNull();
 const managerId=manager.data.user!.id;
 await managerClient.auth.signOut({scope:"local"});
 expect((await admin.from("profiles").update({manager_id:managerId}).eq("id",userId)).error).toBeNull();
 expect((await admin.from("leave_balances").insert({employee_id:userId,year:2026,allocated_days:25})).error).toBeNull();
 expect((await client.auth.signInWithPassword({email,password})).error).toBeNull();
});
test.afterAll(async()=>{
 if(!userId)return;
 const {data:requests}=await client.from("requests").select("id,status").eq("requester_id",userId);
 for(const request of requests||[])if(!["approved","rejected","cancelled"].includes(request.status))await client.rpc("cancel_hr_request",{p_request_id:request.id});
 // Remove only this randomly-created test user's data; never reset the application database.
 execFileSync("docker",["exec","-i","supabase_db_NovaCorp","psql","-U","supabase_admin","-d","postgres","-v","ON_ERROR_STOP=1"],{input:"begin; delete from public.requests where requester_id='"+userId+"'; delete from public.leave_balances where employee_id='"+userId+"'; commit;",encoding:"utf8"});
 expect((await admin.auth.admin.deleteUser(userId)).error).toBeNull();
});
async function login(page:Page){
 await page.goto("/connexion");await page.getByLabel("Adresse email professionnelle").fill(email);
 await page.getByLabel("Mot de passe",{exact:true}).fill(password);
 await page.getByRole("button",{name:"Se connecter",exact:true}).click();await expect(page).toHaveURL(/\/tableau-de-bord$/);
}
for(const kind of ["leave","remote_work","equipment","training"]){
 test("brouillon, modification, soumission et annulation : "+kind,async({page})=>{
 await login(page);await page.getByRole("main").getByRole("link",{name:"Nouvelle demande"}).click();
 await expect(page).toHaveURL(/\/demandes\/nouvelle$/);
 await expect(page.getByLabel("Titre",{exact:false})).toBeVisible();
 await page.getByLabel("Type de demande").selectOption(kind);
 const title="Interface "+kind;
 await page.getByLabel("Titre", {exact:false}).fill(title);
 await page.getByLabel("Motif et précisions").fill("Demande fictive du test navigateur.");
 if(kind!=="equipment"){await page.getByLabel("Date de début").fill("2026-11-02");await page.getByLabel("Date de fin").fill("2026-11-03");}
 if(kind==="equipment"||kind==="training")await page.getByLabel("Montant estimé").fill("100,50");
 if(kind==="training")await page.getByLabel("Organisme de formation").fill("Centre test");
 await page.getByRole("button",{name:"Enregistrer le brouillon"}).click();
 await expect(page.getByRole("heading",{name:title,exact:true})).toBeVisible();
 const detailUrl=page.url();const id=detailUrl.split("/").pop()!;
 await expect(page.locator(".status-draft")).toBeVisible();
 await page.getByRole("link",{name:"Modifier le brouillon"}).click();
 await expect(page.getByLabel("Titre",{exact:false})).toHaveValue(title);
 await page.getByLabel("Titre",{exact:false}).fill(title+" modifié");
 await page.getByRole("button",{name:"Soumettre la demande"}).click();
 await expect(page).toHaveURL(detailUrl);
 await expect(page.getByText("Soumise",{exact:true}).first()).toBeVisible();
 expect((await client.from("requests").select("status,requested_days,amount").eq("id",id).single()).data?.status).toBe("submitted");
 if(kind==="leave"){await expect(page.getByText("Jours décomptés")).toBeVisible();expect((await client.from("leave_balances").select("reserved_days").eq("employee_id",userId).single()).data?.reserved_days).toBe(2);}
 await expect(page.getByRole("link",{name:"Modifier le brouillon"})).toHaveCount(0);
 await page.screenshot({path:"test-results/demande-"+kind+".png",fullPage:true});
 await page.getByRole("button",{name:"Annuler la demande",exact:true}).click();
 await page.getByRole("button",{name:"Confirmer l’annulation"}).click();
 await expect(page.getByText("Annulée",{exact:true}).first()).toBeVisible();
 expect((await client.from("leave_balances").select("reserved_days").eq("employee_id",userId).single()).data?.reserved_days).toBe(0);
 });
}
test("un solde insuffisant conserve un seul brouillon et les champs saisis",async({page})=>{
 await login(page);await page.goto("/tableau-de-bord/demandes/nouvelle");
 await page.getByLabel("Titre",{exact:false}).fill("Solde insuffisant");
 await page.getByLabel("Date de début").fill("2026-10-01");
 await page.getByLabel("Date de fin").fill("2026-11-30");
 await page.getByRole("button",{name:"Soumettre la demande"}).click();
 await expect(page.locator("form [role=alert]")).toContainText("Solde");
 await expect(page.getByRole("button",{name:"Soumettre la demande"})).toBeEnabled();
 await expect(page.getByLabel("Titre",{exact:false})).toHaveValue("Solde insuffisant");
 await page.getByRole("button",{name:"Soumettre la demande"}).click();
 await expect(page.locator("form [role=alert]")).toContainText("Solde");
 await expect(page.getByRole("button",{name:"Soumettre la demande"})).toBeEnabled();
 const {data}=await client.from("requests").select("id,status").eq("title","Solde insuffisant");expect(data).toHaveLength(1);expect(data![0].status).toBe("draft");
 await page.getByLabel("Date de fin").fill("2026-10-02");
 await page.getByRole("button",{name:"Soumettre la demande"}).click();
 await expect(page.getByText("Soumise",{exact:true}).first()).toBeVisible();
});
test("filtres, isolation d’un brouillon et formulaire mobile",async({page,browser})=>{
 const fixture=await client.from("requests").insert({title:"Filtre annulation",request_type:"equipment",requester_id:userId}).select("id").single();expect(fixture.error).toBeNull();expect((await client.rpc("cancel_hr_request",{p_request_id:fixture.data!.id})).error).toBeNull();
 await login(page);await page.getByLabel("Statut",{exact:true}).selectOption("cancelled");
 await expect(page).toHaveURL(/status=cancelled/);
 await expect(page.locator(".request-card .status:not(.status-cancelled)")).toHaveCount(0);
 await expect(page.getByRole("heading",{name:"Filtre annulation",exact:true})).toBeVisible();for(const badge of await page.locator(".request-card .status").all())await expect(badge).toHaveText("Annulée");
 const {data:draft,error}=await client.from("requests").insert({title:"Brouillon privé",request_type:"equipment",requester_id:userId}).select("id").single();expect(error).toBeNull();
 const other=await browser.newContext();const outsider=await other.newPage();
 await outsider.goto("/connexion");await outsider.getByLabel("Adresse email professionnelle").fill("salarie@novacorp.test");await outsider.getByLabel("Mot de passe",{exact:true}).fill(password);await outsider.getByRole("button",{name:"Se connecter",exact:true}).click();await expect(outsider).toHaveURL(/\/tableau-de-bord$/);
 const response=await outsider.goto("/tableau-de-bord/demandes/"+draft!.id);expect(response?.status()).toBe(404);await other.close();
 await page.setViewportSize({width:390,height:844});await page.goto("/tableau-de-bord/demandes/nouvelle");
 await expect(page.getByRole("button",{name:"Soumettre la demande"})).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:"test-results/demande-mobile.png",fullPage:true});
});
for(const approve of [true,false]){
 test("le manager "+(approve?"approuve":"refuse avec un motif")+" son étape assignée",async({page,browser})=>{
 const {data:r,error}=await client.from("requests").insert({requester_id:userId,request_type:"equipment",title:approve?"Validation interface":"Refus interface",quantity:1,amount:80}).select("id").single();expect(error).toBeNull();const id=r!.id;
 expect((await client.rpc("submit_hr_request",{p_request_id:id})).error).toBeNull();
 // Simulate only the backend preparation: no orchestration is exposed by the UI.
 expect((await admin.rpc("transition_hr_request",{p_request_id:id,p_status:"under_review"})).error).toBeNull();
 expect((await admin.rpc("prepare_hr_approvals",{p_request_id:id})).error).toBeNull();
 expect((await admin.from("ai_reviews").insert({request_id:id,provider:"test",model:"fictif",prompt_version:"v1",status:"succeeded",qualification:"eligible",summary:"Synthèse fictive du test navigateur",rag_context:{method:"postgres_fts_fr_v1",passages:[{source_id:"ui-politique@1#1",title:"Document fictif de test",version:"1",section:"Validation",source_path:"ui-politique.md",content:"Extrait fictif : la validation reste humaine."}],citations:["ui-politique@1#1"]},started_at:new Date(Date.now()-60000).toISOString(),finished_at:new Date().toISOString()})).error).toBeNull();
 expect((await admin.rpc("transition_hr_request",{p_request_id:id,p_status:"pending_approval"})).error).toBeNull();
 const {data:step}=await admin.from("approval_steps").select("id").eq("request_id",id).eq("position",1).single();
 expect((await admin.from("approval_steps").update({status:"pending"}).eq("id",step!.id)).error).toBeNull();
 await login(page);await page.goto("/tableau-de-bord/demandes/"+id);
 await expect(page.getByRole("button",{name:"Approuver",exact:true})).toHaveCount(0);
 const managerContext=await browser.newContext();const managerPage=await managerContext.newPage();
 try{
 await managerPage.goto("/connexion");await managerPage.getByLabel("Adresse email professionnelle").fill("manager@novacorp.test");await managerPage.getByLabel("Mot de passe",{exact:true}).fill(password);await managerPage.getByRole("button",{name:"Se connecter",exact:true}).click();await expect(managerPage).toHaveURL(/\/tableau-de-bord$/);
 await managerPage.getByRole("navigation",{name:"Navigation de l’espace"}).getByRole("link",{name:"Mon équipe",exact:true}).click();
 await expect(managerPage.getByRole("heading",{name:"Demandes de mon équipe",exact:true})).toBeVisible();
 await expect(managerPage.getByRole("navigation",{name:"Navigation de l’espace"}).getByRole("link",{name:"Mon équipe",exact:true})).toHaveAttribute("aria-current","page");
 await managerPage.goto("/tableau-de-bord/demandes/"+id);
 await expect(managerPage.getByText("Synthèse fictive du test navigateur",{exact:true})).toBeVisible();
 await expect(managerPage.getByRole("heading",{name:"Sources documentaires",exact:true})).toBeVisible();
 await managerPage.locator(".rag-sources summary").click();
 await expect(managerPage.getByText("Extrait fictif : la validation reste humaine.",{exact:true})).toBeVisible();
 await expect(page.getByRole("heading",{name:"Sources documentaires",exact:true})).toHaveCount(0);
 if(!approve){
 await managerPage.getByRole("button",{name:"Refuser",exact:true}).click();
 await expect(managerPage.locator("form [role=alert]")).toContainText("Un motif est obligatoire");
 await expect(managerPage.getByRole("button",{name:"Refuser",exact:true})).toBeEnabled();
 await managerPage.getByLabel("Commentaire (obligatoire pour refuser)").fill("Besoin à préciser.");
 }
 await managerPage.getByRole("button",{name:approve?"Approuver":"Refuser",exact:true}).click();
 await expect(managerPage.getByRole("button",{name:"Approuver",exact:true})).toHaveCount(0);
 expect((await admin.from("approval_steps").select("status,decision_comment").eq("id",step!.id).single()).data?.status).toBe(approve?"approved":"rejected");
 // The employee's open view receives the actual persisted decision.
 await expect(page.getByText(approve?"Approuvée":"Refusée",{exact:true})).toBeVisible();
 expect((await client.from("requests").select("status").eq("id",id).single()).data?.status).toBe("pending_approval");
 }finally{await managerContext.close();}
 });
}

test("pagination, filtres immédiats et retour navigateur",async({page})=>{
 const rows=Array.from({length:25},(_,index)=>({requester_id:userId,request_type:"training",title:"Pagination formation "+index}));
 const created=await client.from("requests").insert(rows).select("id");expect(created.error).toBeNull();
 try {
  await login(page);
  await expect(page.getByRole("navigation",{name:"Navigation de l’espace"}).getByRole("link",{name:"Mes demandes",exact:true})).toHaveAttribute("aria-current","page");
  await page.getByLabel("Type de demande",{exact:true}).selectOption("training");
  await expect(page).toHaveURL(/type=training/);
  await page.getByLabel("Statut",{exact:true}).selectOption("draft");
  await expect(page).toHaveURL(/status=draft/);
  await expect(page.getByRole("button",{name:"Filtrer",exact:true})).toHaveCount(0);
  await expect(page.locator(".request-card")).toHaveCount(5);
  const firstTitles=await page.locator(".request-card h3").allTextContents();
  const pagination=page.getByRole("navigation",{name:"Pagination",exact:true});
  await pagination.getByRole("link",{name:"Page suivante",exact:true}).click();
  await expect(page).toHaveURL(/page=2/);
  await expect(page.locator(".request-card")).toHaveCount(5);
  expect((await page.locator(".request-card h3").allTextContents()).some(title=>firstTitles.includes(title))).toBe(false);
  await expect(page.getByLabel("Type de demande",{exact:true})).toHaveValue("training");
  await page.getByLabel("Statut",{exact:true}).selectOption("cancelled");
  await expect(page).toHaveURL(/status=cancelled/);
  expect(new URL(page.url()).searchParams.has("page")).toBe(false);
  await expect(pagination).toContainText("Page 1 sur 1");
  for(const badge of await page.locator(".request-card .status").all())await expect(badge).toHaveText("Annulée");
  await page.goBack();
  await expect(page.getByLabel("Statut",{exact:true})).toHaveValue("draft");
  await expect(page.locator(".request-card")).toHaveCount(5);
  await page.goto("/tableau-de-bord?type=training&status=draft&page=9999");
  await expect(pagination).toContainText("Page 5 sur 5");
  await expect(page.locator(".request-card")).toHaveCount(5);
  await page.setViewportSize({width:390,height:844});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:"test-results/navigation-pagination-mobile.png",fullPage:true});
 } finally {
  // Only the disposable test user's drafts created above.
  execFileSync("docker",["exec","-i","supabase_db_NovaCorp","psql","-U","supabase_admin","-d","postgres","-v","ON_ERROR_STOP=1"],{input:"delete from public.requests where requester_id='"+userId+"' and id in ("+(created.data||[]).map(row=>"'"+row.id+"'").join(",")+");",encoding:"utf8"});
 }
});
