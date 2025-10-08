import Array "mo:core/Array";
import Error "mo:core/Error";
import Map "mo:core/pure/Map";
import Prim "mo:prim";
import Principal "mo:core/Principal";

// import Scheduler "./scheduler";

shared persistent actor class StatusProxy() {

  type ManagementCanisterActor = actor {
    update_settings : shared ({
      canister_id : Principal;
      settings : { controllers : ?[Principal] };
    }) -> async ();
    canister_status : shared ({ canister_id : Principal }) -> async CanisterStatus;
  };
  type CanisterStatus = {
    status : { #stopped; #stopping; #running };
    settings : DefiniteCanisterSettings;
    module_hash : ?Blob;
    memory_size : Nat;
    memory_metrics : MemoryMetrics;
    cycles : Nat;
    idle_cycles_burned_per_day : Nat;
    reserved_cycles : Nat;
    query_stats : QueryStats;
  };
  type MemoryMetrics = {
    wasm_memory_size : Nat;
    stable_memory_size : Nat;
    global_memory_size : Nat;
    wasm_binary_size : Nat;
    custom_sections_size : Nat;
    canister_history_size : Nat;
    wasm_chunk_store_size : Nat;
    snapshots_size : Nat;
  };
  type DefiniteCanisterSettings = {
    controllers : [Principal];
    compute_allocation : Nat;
    memory_allocation : Nat;
    freezing_threshold : Nat;
    reserved_cycles_limit : Nat;
    log_visibility : { #controllers; #allowed_viewers : [Principal]; #public_ };
    wasm_memory_limit : Nat;
  };
  type QueryStats = {
    num_calls_total : Nat;
    num_instructions_total : Nat;
    request_payload_bytes_total : Nat;
    response_payload_bytes_total : Nat;
  };

  transient let ic : ManagementCanisterActor = actor ("aaaaa-aa");

  transient let CONSTANTS = {
    CACHE_TTL = 60 : Nat64; // temporarily use 1 minute cache TTL

    // CACHE_TTL = 21_600 : Nat64; // do not reload state if cache is younger than 6 hours
    // CACHE_KEEP_TTL = 86_400 : Nat64; // do not remove canister id from cache for 24 hours after last update
    // CLEANUP_INTERVAL = 86_400 : Nat64; // cleanup each 24 hours
    // CLEANUP_INTERVAL_BIAS = 0 : Nat64; // bias 0 for 24h interval means "at UTC midnight"
  };

  var cache : Map.Map<Principal, (Nat64, CanisterStatus)> = Map.empty();

  public shared query func queryState(canisterId : Principal) : async ?(Nat64, CanisterStatus) {
    Map.get(cache, Principal.compare, canisterId);
  };

  public shared func loadState(canisterId : Principal) : async (Nat64, CanisterStatus) {
    let now = Prim.time() / 1_000_000_000;
    switch (Map.get(cache, Principal.compare, canisterId)) {
      case (?(cacheTS, data)) if (cacheTS + CONSTANTS.CACHE_TTL > now) {
        return (cacheTS, data);
      };
      case (null) {};
    };
    let statusResponse = await ic.canister_status({ canister_id = canisterId });
    cache := Map.add(cache, Principal.compare, canisterId, (now, statusResponse));
    (now, statusResponse);
  };

  // transient let cleanupSchedule = Scheduler.Scheduler(
  //   CONSTANTS.CLEANUP_INTERVAL,
  //   CONSTANTS.CLEANUP_INTERVAL_BIAS,
  //   func(_ : Nat) : async* () {
  //     let now = Prim.time() / 1_000_000_000;
  //     cache := Map.filter(
  //       cache,
  //       Principal.compare,
  //       func(_ : Principal, (ts : Nat64, _ : CanisterStatus)) : Bool = ts + CONSTANTS.CACHE_KEEP_TTL > now,
  //     );
  //   },
  // );

  // cleanupSchedule.start<system>();

  // public shared func restartCleanupScheduleTimer() : async () {
  //   // restart timer only if timer did not run for 48 hours straight
  //   if (cleanupSchedule.lastExecutionTimestamp() + 172_800_000_000_000 < Prim.time()) {
  //     cleanupSchedule.stop();
  //     cleanupSchedule.start<system>();
  //   };
  // };

  public shared func temporary_backdoor_undo_immutability(canisterId : Principal) : async Text {
    let backendPrincipal = Principal.fromText("i2qrn-wou4z-zo3z2-g6vlg-dma7w-siosb-tfkdt-gw2ut-s2tmr-66dzg-fae");
    let state = try {
      await ic.canister_status({ canister_id = canisterId });
    } catch (err) {
      return "Error while fetching canister status: " # Error.message(err);
    };
    switch (Array.indexOf(state.settings.controllers, Principal.equal, backendPrincipal)) {
      case (?_) return "Not frozen";
      case (null) {};
    };
    try {
      await ic.update_settings({
        canister_id = canisterId;
        settings = {
          controllers = ?Array.flatten([state.settings.controllers, [backendPrincipal]]);
        };
      });
    } catch (err) {
      return "Error while updating canister status: " # Error.message(err);
    };
    "Done";
  };

};
