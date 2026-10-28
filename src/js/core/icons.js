// Shared stroke icons. Paths are static; labels always come from accessible text.
const paths = Object.freeze({
 LayoutDashboard:'M3 3h7v7H3z M14 3h7v4h-7z M14 11h7v10h-7z M3 14h7v7H3z',
 Building2:'M4 21V5l8-3 8 3v16 M2 21h20 M9 21v-4h6v4 M8 7h1 M15 7h1 M8 11h1 M15 11h1',
 ClipboardList:'M9 4H5v17h14V4h-4 M9 2h6v5H9z M8 11h8 M8 15h8',
 UsersRound:'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2 M16 4a4 4 0 0 1 0 8 M22 21v-2a4 4 0 0 0-3-3.87 M9 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8',
 UserRound:'M20 21v-2a6 6 0 0 0-6-6h-4a6 6 0 0 0-6 6v2 M12 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8',
 CalendarDays:'M4 5h16v16H4z M16 3v4 M8 3v4 M4 11h16 M8 15h1 M15 15h1',
 MessageSquareText:'M21 15a3 3 0 0 1-3 3H8l-5 4V6a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3z M7 8h10 M7 12h7',
 Boxes:'m12 3 9 5-9 5-9-5z M3 8v10l9 5 9-5V8 M12 13v10 M7.5 5.5l9 5',
 ShoppingBag:'M5 7h14l2 14H3z M9 7V5a3 3 0 0 1 6 0v2',
 SlidersHorizontal:'M3 6h5 M12 6h9 M3 18h9 M16 18h5 M8 3v6 M12 15v6',
 UtensilsCrossed:'M4 3v5a3 3 0 0 0 6 0V3 M7 3v18 M20 21V3c-4 2-5 8 0 10',
 Plus:'M12 5v14 M5 12h14',
 ArrowUpRight:'M7 17 17 7 M7 7h10v10',
 ArrowRight:'M5 12h14 M13 6l6 6-6 6',
 ChevronRight:'m9 5 7 7-7 7',
 Search:'M10.5 3a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15 M16 16l5 5',
 Refresh:'M20 7v5h-5 M4 17v-5h5 M6.1 6a8 8 0 0 1 13.4 3 M4.5 15A8 8 0 0 0 17.9 18',
 ShieldCheck:'m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6z m-4 9 3 3 5-5',
 Check:'m5 12 4 4L19 6',
 Pause:'M8 5v14 M16 5v14',
 Bell:'M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9 M10 21h4',
 Sun:'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M12 2v2 M12 20v2 M2 12h2 M20 12h2 M5 5l1.5 1.5 M17.5 17.5l1.5 1.5 M5 19l1.5-1.5 M17.5 6.5l1.5-1.5',
 Moon:'M20.9 13A9 9 0 0 1 11 3.1 9 9 0 1 0 20.9 13',
 LogOut:'M9 5H4v14h5 M10 12h11 M17 8l4 4-4 4',
 More:'M5 12h.01 M12 12h.01 M19 12h.01',
 Close:'m6 6 12 12 M6 18 18 6',
 CircleHelp:'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18 M9.1 9a3 3 0 0 1 5.8 1c0 2-3 2-3 4 M12 17h.01'
});
export function icon(name, className='ui-icon') {
 const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
 for(const [key,value] of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor','stroke-width':'1.7','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true',focusable:'false',class:className}))svg.setAttribute(key,value);
 const path=document.createElementNS(svg.namespaceURI,'path');
 path.setAttribute('d',paths[name]||paths.CircleHelp);svg.append(path);return svg;
}
