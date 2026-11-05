// Loads the staff/admin controllers only for people who need them.
// Access control is unchanged: the server still checks every request, and the
// workspace still decides which sections a verified context may open.
export const STAFF_ROLES=Object.freeze(['bartender','warehouse_manager','school_admin','platform_admin']);
// Set once a staff context has opened on this device. On later visits the
// chunk is fetched straight away, so it is in the service worker cache before
// the network drops and the offline Barista terminal can still start.
export const STAFF_DEVICE_KEY='breakapp:staff-modules-v1';

function defaultStorage(){
  try{return globalThis.localStorage||null;}catch{return null;}
}

export function createRoleModuleLoader(client,{
  importStaff=()=>import('./staff-modules.js'),
  storage=defaultStorage()
}={}){
  let pending=null,initialized=false;
  function load(){
    if(!pending){
      pending=importStaff().then(module=>{
        if(!initialized){initialized=true;module.initializeStaffModules(client);}
      },error=>{pending=null;throw error;});
    }
    return pending;
  }
  return {
    // Returns null when the role needs nothing more (or it is already loaded),
    // otherwise a promise that settles once the controllers are listening.
    prepare(role){
      if(!STAFF_ROLES.includes(role)||initialized)return null;
      try{storage?.setItem(STAFF_DEVICE_KEY,'1');}catch{/* storage denied */}
      return load();
    },
    warm(){
      let known=false;
      try{known=storage?.getItem(STAFF_DEVICE_KEY)==='1';}catch{/* storage denied */}
      if(known)load().catch(()=>{/* retried when a staff context opens */});
      return known;
    },
    get loaded(){return initialized;}
  };
}
