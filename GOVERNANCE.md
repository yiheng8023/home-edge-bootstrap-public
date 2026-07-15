# Governance

[简体中文](GOVERNANCE.zh-CN.md)

Home Edge Bootstrap uses maintainer-led, evidence-based governance. The objective is to keep product,
adapter, compatibility, release, and security decisions reviewable while protecting users from
unsupported network changes and overstated claims.

## Roles and authority

- **Contributors** propose issues, documentation, fixtures, adapters, and code under the contribution
  policy.
- **Reviewers** provide technical, documentation, compatibility, licensing, or security review.
  Review does not by itself grant merge, maturity, support, or release authority.
- **Adapter maintainers** accept ongoing responsibility for a named adapter and its evidence within
  the authority delegated by project maintainers.
- **Project maintainers** own repository policy, approve and merge changes, coordinate security
  reports, assign adapter maturity, and authorize releases.

The current project maintainer is `@yiheng8023`. Additional maintainers may be appointed after
sustained, trusted contributions and demonstrated review judgment.

## Decision standard

Routine changes are decided through issue and pull-request review. Maintainers may request additional
evidence or decline changes that weaken safety, portability, licensing clarity, recovery,
maintainability, or public claim accuracy.

A material behavior, adapter, compatibility, or governance change should record:

1. the user-visible problem and affected subjects;
2. the capability and authority boundary;
3. alternatives considered, including reuse of mature existing components;
4. synthetic and platform evidence;
5. rollback, failure, and maintenance behavior; and
6. documentation and support impact in both operator languages where applicable.

When consensus is unavailable, project maintainers make the final repository decision and record the
reason. Security-sensitive details may remain confidential until disclosure is safe.

## Adapter lifecycle

Adapter maturity and target support classification are independent:

- **External integration** — maintained outside the repository; no project maturity or support claim.
- **Experimental adapter** — admitted for bounded development with an owner and synthetic evidence;
  interfaces may change and field support is not implied.
- **Community-maintained adapter** — has accountable maintenance, documented contracts, fixtures,
  recovery behavior, and a reviewed support boundary.
- **Verified adapter** — additionally satisfies the project-defined evidence gates for its declared
  compatibility range and retains accountable maintenance.

The current Merlin implementation is the implemented reference adapter; that role does not assign it a verified maturity stage.

Admission or promotion requires a bounded adapter identity, capability contract, target-support
policy, fail-closed checks, backup and rollback behavior, diagnostics that do not expose sensitive information, bilingual operator
guidance, licensing clarity, and a named maintenance owner. Similarity to an existing adapter,
popularity, or success on one target is not sufficient evidence. A change may remain external or at a
lower maturity stage when its evidence or maintenance capacity is insufficient.

Project maintainers may demote, freeze, or retire an adapter when evidence becomes stale, maintenance
ownership disappears, compatibility drifts, or continued inclusion would mislead users. The decision
must preserve a migration or rollback path where practical.

## Compatibility and claims

Fixtures demonstrate script behavior against controlled inputs. They do not certify specific
hardware, firmware, providers, networks, or permanent availability. Each adapter declares target
support classifications separately from maturity. Public statements, repository topics, issue labels,
release notes, and promotional material must use the same approved terminology and must not broaden
the evidence.

## Releases

Project maintainers authorize releases only after the applicable source, licensing, multi-platform,
artifact, and release-readiness checks pass. A merged pull request, sponsorship, or adapter maturity
change is not by itself a release commitment.

## Sponsorship and influence

Sponsorship does not purchase merge authority, adapter maturity, compatibility claims, support
priority, release timing, security decisions, or feature entitlement. Material conflicts of interest
should be disclosed to reviewers and maintainers.

## Changes to governance

Governance changes use the same review process as other material changes. They require a clear
problem statement, impact analysis, verification or review surface, and maintainer approval.
