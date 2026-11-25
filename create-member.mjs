import {createClient} from '@supabase/supabase-js';
export const handler=async event=>{
 const reply=(statusCode,data)=>({statusCode,headers:{'Content-Type':'application/json','Cache-Control':'no-store'},body:JSON.stringify(data)});
 if(event.httpMethod!=='POST')return reply(405,{error:'POST required'});
 try{
 const url=process.env.SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!key)return reply(503,{error:'Server credentials not configured'});
 const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 const token=(event.headers.authorization||'').replace(/^Bearer /i,'');
 const {data:{user},error}=await db.auth.getUser(token);if(error||!user)return reply(401,{error:'Sign in required'});
 const a=await db.from('hub_admins').select('id').eq('id',user.id).maybeSingle();if(a.error||!a.data)return reply(403,{error:'Admin only'});
 const {email,password,name,rank}=JSON.parse(event.body||'{}');
 if(![email,password,name,rank].every(x=>typeof x==='string')||password.length<12||!name.trim()||name.length>60||!rank.trim()||rank.length>60)return reply(400,{error:'Enter valid details and a password of at least 12 characters'});
 const created=await db.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{display_name:name}});if(created.error)return reply(400,{error:created.error.message});
 const id=created.data.user.id;const member=await db.from('hub_members').insert({id,name,rank});if(member.error){await db.auth.admin.deleteUser(id);return reply(500,{error:'Member creation failed; check Supabase users before retrying'});}
 return reply(200,{id});
 }catch{return reply(500,{error:'Account creation failed'});}
};
