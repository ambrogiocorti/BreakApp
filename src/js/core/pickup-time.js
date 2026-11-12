// Pickup windows are stored as a school-local date and time (Europe/Rome).
// A window is selectable only until it starts: the server applies the same
// rule (app_private.window_bookable, submit_individual_order, create_group_draft).
const ROME='Europe/Rome';
function romeParts(now){
  const parts=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:ROME,hourCycle:'h23',
    year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit'})
    .formatToParts(now).map(p=>[p.type,p.value]));
  return {date:`${parts.year}-${parts.month}-${parts.day}`,time:`${parts.hour}:${parts.minute}:${parts.second}`};
}
export function romeToday(now=new Date()){return romeParts(now).date;}
export function isUpcomingWindow(window,now=new Date()){
  if(!window?.service_date||!window?.starts_at)return false;
  const {date,time}=romeParts(now);
  const raw=String(window.starts_at).slice(0,8);
  const start=raw.length===5?raw+':00':raw;
  return window.service_date>date||(window.service_date===date&&start>time);
}
