export const demoEmail="demo.salarie@novacorp.test";
export const demoPassword="NovaCorpDemo2026!";
export function demoScenarios(year){
 const monday=new Date(Date.UTC(year+1,0,1));while(monday.getUTCDay()!==1)monday.setUTCDate(monday.getUTCDate()+1);
 const day=(week,offset=0)=>new Date(monday.getTime()+(week*7+offset)*86400000).toISOString().slice(0,10);
 const rows=[
 ["leave","draft","Préparer des congés",0],["remote_work","draft","Préparer du télétravail",1],
 ["equipment","draft","Préparer un écran",null,350],["training","draft","Préparer une formation",2,450],
 ["leave","submitted","Congés à qualifier",4],["remote_work","submitted","Télétravail à qualifier",5],
 ["equipment","submitted","Casque à qualifier",null,120],["training","submitted","Formation à qualifier",6,800],
 ["leave","manager","Congés à valider par le manager",8],["remote_work","manager","Télétravail à valider",9],
 ["equipment","hr","Écran à valider par les RH",null,750],["training","hr","Formation à valider par les RH",10,1200],
 ["leave","director","Congés de 11 jours à valider par la DRH",12],
 ["equipment","director","Ordinateur à valider par la DRH",null,1800],
 ["training","director","Formation à valider par la DRH",15,2200],
 ["leave","approved","Congés approuvés",18],["equipment","approved","Clavier approuvé",null,90],
 ["training","rejected","Formation refusée",20,1700],["remote_work","cancelled","Télétravail annulé",22],
 ["equipment","failed","Qualification en échec",null,230],
 ["equipment","overdue_hr","Validation RH en retard",null,650],
 ["remote_work","reminder_manager","Relance manager à 24 h",24],
 ["equipment","reminder_director","Relance DRH à 24 h",null,1600]
 ];
 return rows.map(([type,stage,title,week,amount],i)=>({
  id:"d3e00000-0000-4000-8000-"+String(i+1).padStart(12,"0"),
  request_type:type,stage,title:"[Démo] "+title,description:"Donnée fictive de démonstration NovaCorp. Aucun besoin réel.",
  start_date:week===null?null:day(week),end_date:week===null?null:day(week,type==="leave"?(stage==="director"?14:1):0),
  amount:amount??null,quantity:type==="equipment"?1:null,
  training_provider:type==="training"?"Centre de formation fictif":null,
  age_hours:({draft:0,submitted:0,manager:3,hr:12,director:18,approved:72,rejected:48,cancelled:24,failed:1,overdue_hr:56,reminder_manager:26,reminder_director:38})[stage]
 }));
}
