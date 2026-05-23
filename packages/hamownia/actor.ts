/** Test actor definitions and factory. @module actor */

/** A test actor with PDS-issued credentials. Represents the identity of a user. */
export class Actor {
  /** DID assigned after account creation. */
  public did: string = "";
  /** Access JWT assigned after account creation or login. */
  public accessJwt: string = "";
  /** Refresh JWT assigned after account creation or login. */
  public refreshJwt: string = "";

  /**
   * Create a test actor.
   * @param name - Human-readable display name
   * @param handle - ATProto handle
   * @param email - Account email
   * @param password - Account password
   * @param persona - Scenario persona description
   * @param role - Scenario role
   * @param pdsUrl - PDS URL assigned to the actor
   */
  constructor(
    public name: string,
    public handle: string,
    public email: string,
    public password: string,
    public persona: string,
    public role: "user" | "admin" | "mod" = "user",
    public pdsUrl: string = "",
  ) {}

  /** Current access token for authenticated calls. */
  get token(): string {
    return this.accessJwt;
  }
}

/** Actor template used for creating factory instances. */
export interface ActorTemplate {
  name: string;
  handle: string;
  email: string;
  password: string;
  persona: string;
  role: "user" | "admin" | "mod";
  /** Which PDS to assign to: "pds1" or "pds2" */
  pds: "pds1" | "pds2";
}

let _actorCounter = 0;

/**
 * Factory for creating test actors deterministically.
 */
export class ActorFactory {
  private suffix: string;

  constructor(
    private pds1Url: string = "http://localhost:2583",
    private pds2Url: string = "http://localhost:2587",
  ) {
    this.suffix = `${Deno.pid}-${(++_actorCounter).toString(16).padStart(4, "0")}`;
  }

  /**
   * Generates a unique actor from a given template, ensuring handles and emails don't collide.
   */
  public createFromTemplate(tpl: ActorTemplate): Actor {
    const handleParts = tpl.handle.split(".");
    const handle = handleParts.length > 1
      ? `${handleParts[0]}-${this.suffix}.${handleParts.slice(1).join(".")}`
      : `${tpl.handle}-${this.suffix}`;

    const emailParts = tpl.email.split("@");
    const email = `${emailParts[0]}-${this.suffix}@${emailParts[1]}`;

    const pdsUrl = tpl.pds === "pds2" ? this.pds2Url : this.pds1Url;

    return new Actor(
      tpl.name,
      handle,
      email,
      tpl.password,
      tpl.persona,
      tpl.role,
      pdsUrl,
    );
  }
}
