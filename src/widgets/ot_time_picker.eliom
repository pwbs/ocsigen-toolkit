(* Ocsigen
 * http://www.ocsigen.org
 * Copyright (C) 2015
 * Vasilis Papavasileiou
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*)

{shared{

open Eliom_shared.React.S.Infix
open Eliom_content.Html5.D

type polar = int * int

type cartesian = int * int

type time_receiver = (int -> int -> unit) Eliom_lib.client_value

type 'a rf = ?step:React.step -> 'a -> unit

type 'a rp = 'a React.signal * 'a rf

let r_node = Eliom_content.Html5.R.node

(* utils *)

let rec list_init ?acc:(acc = []) i f =
  if i <= 0 then
    acc
  else
    let acc = f (i - 1) :: acc in
    list_init ~acc (i - 1) f

(* http://stackoverflow.com/questions/30732709 *)

let round_lb = -.(2. ** 52.)

let round_ub = 2. ** 52.

let round x =
  if round_lb <= x && x <= round_ub then
    floor (x +. 0.49999999999999994)
  else
    x

(* polar / cartesian / hours:minutes conversions *)

(* functions perform implicit rotation, so that angle = 0 means noon /
   midnight *)

let center_x = 50

let center_y = 50

let polar_to_cartesian (r, h) =
  let r = float_of_int r
  and h = float_of_int h in
  let h = h *. 3.14159 /. 180. in
  let x = center_x + int_of_float (r *. sin h)
  and y = center_y - int_of_float (r *. cos h) in
  x, y

let pi = 3.14159

let cartesian_to_polar (x, y) =
  let x = float_of_int (x - center_x)
  and y = float_of_int (y - center_y) in
  let r = hypot x y |> round |> int_of_float
  and e =
    let e = atan2 y x *. 180. /. pi |> round |> int_of_float in
    (e + 450) mod 360
  in
  r, e

let cartesian_to_angle (x, y) =
  cartesian_to_polar (x, y) |> snd

let round_5_minutes ?round_5:(round_5 = false) m =
  if round_5 then
    let m = m mod 60 in
    let m =
      if m mod 5 > 2 then
        (m / 5) * 5 + 5
      else
        m / 5 * 5
    in
    if m >= 60 then 55 else m
  else
    m

let angle_to_hours_minutes ?round_5:(round_5 = false) e =
  let m = e * 2 in
  let h = m / 60
  and m =
    let m = m mod 60 in
    if round_5 then
      if m mod 5 > 2 then
        (m / 5) * 5 + 5
      else
        m / 5 * 5
    else
      m
  in
  let m =
    if m >= 60 then
      if round_5 then 55 else 59
    else
      m
  in
  assert (0 <= h && h <= 11);
  assert (0 <= m && m <= 59);
  h, m

let angle_to_hours e =
  let h, m = angle_to_hours_minutes e in
  let h = if m > 30 then h + 1 else h in
  if h = 12 then 0 else h

let angle_to_minutes e =
  let m = e / 6 in
  assert (0 <= m && m <= 59);
  if m = 60 then 0 else m

let angle_to_minutes_round e =
  let m = e / 30 * 5 in
  assert (0 <= m && m <= 59);
  if e mod 30 >= 15 && m <= 50 then
    m + 5
  else
    m

let angle_to_minutes ?round_5:(round_5 = false) e =
  if round_5 then
    angle_to_minutes_round e
  else
    angle_to_minutes e

let cartesian_to_hours_minutes (x, y) =
  cartesian_to_polar (x, y) |> snd |> angle_to_hours_minutes

let cartesian_of_i ?radius:(radius = 40) de i =
  let e = i * de in
  polar_to_cartesian (radius, e)

}}

{shared{

let clock_reactive_hand
    ?radius:(radius = Eliom_shared.React.S.const 31)
    e =
  let a =
    let d =
      Eliom_shared.React.S.l2
        {shared#int -> int -> string{
           fun r e ->
             let x, y = polar_to_cartesian (r, e) in
             Printf.sprintf "M %d %d L %d %d" %center_x %center_y x y
         }}
        radius e
    in
    [Eliom_content.Svg.D.a_class ["ot-tp-hand"];
     Eliom_content.Svg.R.a_d d]
  in
  Eliom_content.Svg.D.path ~a []

let clock_reactive_hand_circle
    ?radius:(radius = 9)
    ?at_radius:(at_radius = Eliom_shared.React.S.const 40)
    e =
  let a =
    let cx =
      let f =
        {shared#int -> int -> Svg_types.Unit.length{
           fun r e ->
             let x, _ = polar_to_cartesian (r, e) in
             float_of_int x, Some `Px }}
      in
      Eliom_shared.React.S.l2 f at_radius e
    and cy =
      let f =
        {shared#int -> int -> Svg_types.Unit.length{
           fun r e ->
             let _, y = polar_to_cartesian (r, e) in
             float_of_int y, Some `Px }}
      in
      Eliom_shared.React.S.l2 f at_radius e
    in
    Eliom_content.Svg.[
      D.a_class ["ot-tp-hand-circle"];
      D.a_r (float_of_int radius, Some `Px);
      R.a_cx cx;
      R.a_cy cy]
  in
  Eliom_content.Svg.D.circle ~a
    Eliom_content.Svg.D.[title (pcdata "")]

let make_clock_point
    ?zero_is_12:(zero_is_12 = false)
    extra_attributes radius de step i =
  let open Eliom_content.Svg.F in
  let x, y = cartesian_of_i ~radius de i in
  let a =
    a_class ["ot-tp-text"]
    :: a_dominant_baseline `Central
    :: a_text_anchor `Middle
    :: a_x_list [float_of_int x, Some `Px]
    :: a_y_list [float_of_int y, Some `Px]
    :: extra_attributes
  and txt =
    if i = 0 && zero_is_12 then
      "12"
    else
      string_of_int (step * i)
  in
  text ~a [pcdata txt]

let clock_svg
    ?zero_is_12
    ?extra_attributes:(extra_attributes = [])
    ?n:(n = 12)
    ?step:(step = 1)
    (e : int Eliom_shared.React.S.t) =
  assert (n >= 0 && 360 mod n = 0);
  let de = 360 / n in
  let l =
    make_clock_point ?zero_is_12 extra_attributes 40 de step |>
    list_init n
  and h1 = clock_reactive_hand e
  and h2 = clock_reactive_hand_circle e in
  Eliom_content.Svg.D.g (h1 :: h2 :: l)

let clock_svg_24h
    ?extra_attributes:(extra_attributes = [])
    b h =
  let de = 30 in
  let l1 = list_init 12 (make_clock_point extra_attributes 30 de 1)
  and l2 =
    let f i = make_clock_point extra_attributes 42 de 1 (i + 12) in
    list_init 12 f
  and h1 =
    let radius = b >|= {shared#{ function true -> 24 | false -> 36 }} in
    clock_reactive_hand ~radius h
  and h2 =
    let at_radius =
      b >|= {shared#{ function true -> 30 | false -> 42 }}
    in
    clock_reactive_hand_circle ~radius:6 ~at_radius h
  in
  Eliom_content.Svg.D.g (h1 :: h2 :: l1 @ l2)

let convert_24h is_am h = if is_am then h else h + 12

}} ;;

{client{

   let (>>!) = Js.Opt.iter

let wrap_click_aux ev f =
  ev##currentTarget >>! fun a ->
  let r = a##getBoundingClientRect () in
  let ox = r##left
  and ox' = r##right
  and oy = r##top
  and oy' = r##bottom
  and x = ev##clientX
  and y = ev##clientY in
  assert (ox' > ox);
  assert (oy' > oy);
  let x =
    float_of_int (x - truncate ox) *. 100. /. (ox' -. ox)
    |> truncate
  and y =
    float_of_int (y - truncate oy) *. 100. /. (oy' -. oy)
    |> truncate
  in
  cartesian_to_polar (x, y) |> f

let wrap_click ev (f : _ rf) =
  let f p = f (snd p) in
  wrap_click_aux ev f

let wrap_click_24h ev f_e f_b =
  let f (r, e) = f_b r; f_e e in
  wrap_click_aux ev f

}}

{shared{
   let make_hours_signal h is_am =
     angle_to_hours h |> convert_24h is_am

let make_hm_signal ?round_5 e is_am =
  let h, m = angle_to_hours_minutes ?round_5 e in
  let h = convert_24h is_am h in
  h, m

}} ;;

{shared{

let make_hours_signal =
  Eliom_shared.React.S.l2
    {shared#{ make_hours_signal }}

let make_hm_signal ?round_5 =
  Eliom_shared.React.S.l2
    {shared#{ make_hm_signal ?round_5:%round_5 }}

let make_minutes_signal ?round_5 =
  Eliom_shared.React.S.map
    {shared#{ angle_to_minutes ?round_5:%round_5 }}

let clock_html_wrap s (f : _ Eliom_lib.client_value) =
  let a =
    let open Eliom_content.Svg.F in
    [a_class ["ot-tp-clock"; "ot-tp-click-anywhere"];
     a_viewbox ( 0. , 0. , 100. , 100. );
     a_onclick
       {{ fun ev -> wrap_click ev %f }}]
  in
  Eliom_content.Html5.D.svg ~a [s]

let clock_html_wrap_24h s f_e f_b =
  let a =
    let open Eliom_content.Svg.F in
    [a_class ["ot-tp-clock";
              "ot-tp-clock-24h";
              "ot-tp-click-anywhere"];
     a_viewbox ( 0. , 0. , 100. , 100. );
     a_onclick {{
       fun ev ->
         let step' = React.Step.create () in
         let step =  Some step' in
         let f_b r = %f_b ?step (r <= 35) in
         wrap_click_24h ev (%f_e ?step) f_b;
         React.Step.execute step' }}]
  in
  Eliom_content.Html5.D.svg ~a [s]

let container l = div ~a:[a_class ["ot-tp-container"]] l

let container_24h l =
  div ~a:[a_class ["ot-tp-container"; "ot-tp-container-24h"]] l

let am_pm_toggle ?init_am:(init_am = true) ?update () =
  let init_up = init_am in
  Ot_toggle.make ~init_up ~up_txt:"AM" ~down_txt:"PM" ?update ()

let angle_signal_of_hours h =
  let h = if h >= 12 then h - 12 else h in
  h * 30

let display_minutes m =
  let a = [a_class ["ot-tp-display"]] in
  div ~a [pcdata (string_of_int m)]

let angle_signal_of_minutes =
  Eliom_shared.React.S.map {shared#{ ( * ) 6 }}

let string_of_hours ?h24:(h24 = false) h =
  if h24 then
    string_of_int h
  else if h = 0 || h = 12 then
    "12"
  else if h < 12 then
    string_of_int h
  else
    string_of_int (h - 12)

let display_hours_minutes_seq ?h24:(h24 = false) f (h, m) b =
  let h' =
    let a =
      if b then
        [a_class ["ot-tp-hours"; "ot-tp-active"]]
      else
        [a_class ["ot-tp-hours"; "ot-tp-inactive"];
         a_onclick {{ fun _ -> %f true }}]
    and c = [string_of_hours ~h24 h |> pcdata] in
    span ~a c
  and m =
    let a =
      if b then
        [a_class ["ot-tp-minutes"; "ot-tp-inactive"];
         a_onclick {{ fun _ -> %f false }}]
      else
        [a_class ["ot-tp-minutes"; "ot-tp-active"]]
    and c = [Printf.sprintf "%02d" m |> pcdata] in
    span ~a c
  and a = [a_class ["ot-tp-display"]] in
  if h24 then
    div ~a [h'; pcdata ":"; m]
  else
    div ~a [h'; pcdata ":"; m;
            pcdata (if h < 12 then " AM" else " PM")]

let angle_signal_of_hours_minutes (h, m) =
  let h = if h >= 12 then h - 12 else h in
  h * 30 + m / 2

let combine_inputs_hours_minutes ?round_5 e_h e_m is_am =
  let h = angle_to_hours e_h |> convert_24h is_am
  and m = angle_to_minutes ?round_5 e_m in
  h, m

let angle_signal_of_hours' (h, _) =
  (if h >= 12 then h - 12 else h) * 30

let angle_signal_of_minutes' (_, m) = m * 6

let display_hours h =
  let a = [a_class ["ot-tp-display"]]
  and s = h >|= {shared# int -> string{ Printf.sprintf "%d:00" }} in
  div ~a [Eliom_content.Html5.R.pcdata s]

}}

{shared{

let angle_signal_of_hours =
  Eliom_shared.React.S.map {shared#{ angle_signal_of_hours }}

let make_hours_12h () =
  let e, f_e = Eliom_shared.React.S.create 0
  and c, is_am = am_pm_toggle () in
  let h = make_hours_signal e is_am in
  let e = angle_signal_of_hours h in
  let g =
    let c = clock_svg ~zero_is_12:true e
    and f_e = Eliom_shared.Value.client f_e in
    clock_html_wrap c f_e
  and d = display_hours h in
  container [g; c; d], h

let make_hours_24h () =
  let e, f_e = Eliom_shared.React.S.create 0
  and b, f_b = Eliom_shared.React.S.create true in
  let h = make_hours_signal e b in
  let e = angle_signal_of_hours h in
  let g = clock_html_wrap_24h (clock_svg_24h b e) f_e f_b
  and d = display_hours h in
  container_24h [g; d], h

let make_hours ?h24:(h24 = false) () =
  if h24 then
    make_hours_24h ()
  else
    make_hours_12h ()

let display_minutes m =
  let a = [a_class ["ot-tp-display"]]
  and s = m >|= {shared# int -> string{ string_of_int }} in
  div ~a [Eliom_content.Html5.R.pcdata s]

let make_minutes ?round_5 () =
  let e, f_e = Eliom_shared.React.S.create 0 in
  let m = make_minutes_signal ?round_5 e in
  let e = angle_signal_of_minutes m in
  let g =
    let c = clock_svg ~n:12 ~step:5 e
    and f_e = Eliom_shared.Value.client f_e in
    clock_html_wrap c f_e
  and d = display_minutes m in
  container [g; d], m

let display_hours_minutes ?h24:(h24 = false) s =
  let a = [a_class ["ot-tp-display"]] in
  let s =
    s >|= {shared# int * int -> string{ fun (h, m) ->
      let h24 = %h24 in
      if h24 then
        Printf.sprintf "%d:%02d" h m
      else
        Printf.sprintf "%s:%02d %s" (string_of_hours ~h24 h) m
          (if h < 12 then "AM" else "PM") }}
  in
  div ~a [Eliom_content.Html5.R.pcdata s]

let display_hours_minutes_seq ?h24 f =
  Eliom_shared.React.S.l2
    {shared#{ display_hours_minutes_seq ?h24:%h24 %f }}

let angle_signal_of_hours_minutes =
  Eliom_shared.React.S.map {shared#{ angle_signal_of_hours_minutes }}

let make_hours_minutes ?round_5 () =
  let e, f_e = Eliom_shared.React.S.create 0
  and c, is_am = am_pm_toggle () in
  let hm = make_hm_signal ?round_5 e is_am in
  let e = angle_signal_of_hours_minutes hm in
  let g =
    let c = clock_svg ~zero_is_12:true e
    and f_e = Eliom_shared.Value.client f_e in
    clock_html_wrap c f_e
  and d = display_hours_minutes ~h24:false hm in
  container [g; c; d], hm

let combine_inputs_hours_minutes ?round_5 =
  Eliom_shared.React.S.l3
    {shared#{ combine_inputs_hours_minutes ?round_5:%round_5 }}

let angle_signal_of_hours' =
  Eliom_shared.React.S.map {shared#{ angle_signal_of_hours' }}

let angle_signal_of_minutes' =
  Eliom_shared.React.S.map {shared#{ angle_signal_of_minutes' }}
}}

{shared{

let show_minutes_aux ?action hm f_e_m =
  let e_m = angle_signal_of_minutes' hm
  and f = {{ fun ?step m ->
    %f_e_m ?step m;
    match %action with
    | Some action ->
      let v = React.S.value %hm in
      Lwt.async (fun () -> action v)
    | None ->
      () }}
  in
  clock_html_wrap (clock_svg ~n:12 ~step:5 e_m) f

}}

{client{
let delay f delay =
  Lwt.async (fun () ->
    lwt () = Lwt_js.sleep delay in
    f ();
    Lwt.return ())
}}

{shared{

let make_hours_minutes_seq_24h
    ?action ?init:(init = (0, 0)) ?update ?round_5 () =
  let i_h, i_m = init in
  let i_m = round_5_minutes ?round_5 i_m in
  let e_h, f_e_h = Eliom_shared.React.S.create ((i_h mod 12) * 30)
  and e_m, f_e_m = Eliom_shared.React.S.create (i_m * 6)
  and is_am, f_is_am = Eliom_shared.React.S.create (i_h < 12) in
  (match update with
   | Some update -> {unit{
     let f (h, m) =
       let h, b = if h > 12 then h - 12, false else h, true in
       %f_e_h (h * 30); %f_e_m (m * 6); %f_is_am b
     in
     React.E.map f %update |> ignore }} |> ignore
   | None ->
     ());
  let b, f_b = Eliom_shared.React.S.create true in
  let hm = combine_inputs_hours_minutes ?round_5 e_h e_m is_am in
  let g_h =
    let f_e_h =
      Eliom_lib.create_shared_value
        (Eliom_shared.Value.local f_e_h)
        {{ fun ?step x ->
           %f_e_h ?step x;
           delay (fun () -> %f_b false) 0.3 }}
    and e_h' = angle_signal_of_hours' hm in
    clock_html_wrap_24h (clock_svg_24h is_am e_h') f_e_h f_is_am
  in
  let g =
    b >|= {shared#{ fun b ->
      if b then
        %g_h
      else
        show_minutes_aux ?action:%action %hm %f_e_m }} |>
    r_node
  and d = display_hours_minutes_seq ~h24:true f_b hm b |> r_node in
  container [g; d], hm, {unit -> unit{ fun () -> %f_b true }}

let make_hours_minutes_seq
    ?action ?init:(init = (0, 0)) ?update ?round_5 () =
  let i_h, i_m = init in
  let i_m = round_5_minutes ?round_5 i_m in
  let e_h, f_e_h = Eliom_shared.React.S.create ((i_h mod 12) * 30)
  and e_m, f_e_m = Eliom_shared.React.S.create (i_m * 6)
  and b, f_b = Eliom_shared.React.S.create true in
  let c, is_am =
    let update =
      match update with
      | Some update ->
        {unit{
           let f (h, m) =
             (let h = if h > 12 then h - 12 else h in
              %f_e_h (h * 30)); %f_e_m (m * 6)
           in
           React.E.map f %update |> ignore }} |> ignore;
        Some {bool React.E.t{
          React.E.map (fun (h, _) -> h < 12) %update
        }}
      | None ->
        None
    in
    am_pm_toggle ?update ~init_am:(i_h < 12) ()
  in
  let hm = combine_inputs_hours_minutes ?round_5 e_h e_m is_am in
  let g_h =
    let e_h' = angle_signal_of_hours' hm
    and f_e_h = {{ fun ?step x ->
      %f_e_h ?step x;
      delay (fun () -> %f_b false) 0.3 }}
    in
    clock_html_wrap (clock_svg ~zero_is_12:true e_h') f_e_h
  in
  let g =
    b >|= {shared#{ fun b ->
      if b then
        %g_h
      else
        show_minutes_aux ?action:%action %hm %f_e_m }} |>
    r_node
  and d = display_hours_minutes_seq ~h24:false f_b hm b |> r_node in
  container [g; c; d], hm, {unit -> unit{ fun () -> %f_b true }}

let make_hours_minutes_seq
    ?action ?init ?update ?round_5 ?h24:(h24 = true) () =
  (if h24 then
     make_hours_minutes_seq_24h
   else
     make_hours_minutes_seq) ?action ?init ?update ?round_5 ()

}}
