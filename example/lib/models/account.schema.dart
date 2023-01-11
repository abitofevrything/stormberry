part of 'account.dart';

extension AccountRepositories on Database {
  AccountRepository get accounts => AccountRepository._(this);
}

abstract class AccountRepository
    implements
        ModelRepository,
        KeyedModelRepositoryInsert<AccountInsertRequest>,
        ModelRepositoryUpdate<AccountUpdateRequest>,
        ModelRepositoryDelete<int> {
  factory AccountRepository._(Database db) = _AccountRepository;

  Future<FullAccountView?> queryFullView(int id);
  Future<List<FullAccountView>> queryFullViews([QueryParams? params]);
  Future<UserAccountView?> queryUserView(int id);
  Future<List<UserAccountView>> queryUserViews([QueryParams? params]);
  Future<CompanyAccountView?> queryCompanyView(int id);
  Future<List<CompanyAccountView>> queryCompanyViews([QueryParams? params]);
}

class _AccountRepository extends BaseRepository
    with
        KeyedRepositoryInsertMixin<AccountInsertRequest>,
        RepositoryUpdateMixin<AccountUpdateRequest>,
        RepositoryDeleteMixin<int>
    implements AccountRepository {
  _AccountRepository(super.db) : super(tableName: 'accounts', keyName: 'id');

  @override
  Future<FullAccountView?> queryFullView(int id) {
    return queryOne(id, FullAccountViewQueryable());
  }

  @override
  Future<List<FullAccountView>> queryFullViews([QueryParams? params]) {
    return queryMany(FullAccountViewQueryable(), params);
  }

  @override
  Future<UserAccountView?> queryUserView(int id) {
    return queryOne(id, UserAccountViewQueryable());
  }

  @override
  Future<List<UserAccountView>> queryUserViews([QueryParams? params]) {
    return queryMany(UserAccountViewQueryable(), params);
  }

  @override
  Future<CompanyAccountView?> queryCompanyView(int id) {
    return queryOne(id, CompanyAccountViewQueryable());
  }

  @override
  Future<List<CompanyAccountView>> queryCompanyViews([QueryParams? params]) {
    return queryMany(CompanyAccountViewQueryable(), params);
  }

  @override
  Future<List<int>> insert(List<AccountInsertRequest> requests) async {
    if (requests.isEmpty) return [];
    var rows = await db.query(requests.map((r) => "SELECT nextval('accounts_id_seq') as \"id\"").join('\nUNION ALL\n'));
    var autoIncrements = rows.map((r) => r.toColumnMap()).toList();

    var values = QueryValues();
    await db.query(
      'INSERT INTO "accounts" ( "company_id", "id", "first_name", "last_name", "location" )\n'
      'VALUES ${requests.map((r) => '( ${values.add(r.companyId)}, ${values.add(autoIncrements[requests.indexOf(r)]['id'])}, ${values.add(r.firstName)}, ${values.add(r.lastName)}, ${values.add(LatLngConverter().tryEncode(r.location))} )').join(', ')}\n',
      values.values,
    );
    await db.billingAddresses.insertMany(requests.where((r) => r.billingAddress != null).map((r) {
      return BillingAddressInsertRequest(
          companyId: null,
          accountId: TextEncoder.i.decode(autoIncrements[requests.indexOf(r)]['id']),
          city: r.billingAddress!.city,
          postcode: r.billingAddress!.postcode,
          name: r.billingAddress!.name,
          street: r.billingAddress!.street);
    }).toList());

    return autoIncrements.map<int>((m) => TextEncoder.i.decode(m['id'])).toList();
  }

  @override
  Future<void> update(List<AccountUpdateRequest> requests) async {
    if (requests.isEmpty) return;
    var values = QueryValues();
    await db.query(
      'UPDATE "accounts"\n'
      'SET "company_id" = COALESCE(UPDATED."company_id"::text, "accounts"."company_id"), "first_name" = COALESCE(UPDATED."first_name"::text, "accounts"."first_name"), "last_name" = COALESCE(UPDATED."last_name"::text, "accounts"."last_name"), "location" = COALESCE(UPDATED."location"::point, "accounts"."location")\n'
      'FROM ( VALUES ${requests.map((r) => '( ${values.add(r.companyId)}, ${values.add(r.id)}, ${values.add(r.firstName)}, ${values.add(r.lastName)}, ${values.add(LatLngConverter().tryEncode(r.location))} )').join(', ')} )\n'
      'AS UPDATED("company_id", "id", "first_name", "last_name", "location")\n'
      'WHERE "accounts"."id" = UPDATED."id"',
      values.values,
    );
    await db.billingAddresses.updateMany(requests.where((r) => r.billingAddress != null).map((r) {
      return BillingAddressUpdateRequest(
          accountId: r.id,
          city: r.billingAddress!.city,
          postcode: r.billingAddress!.postcode,
          name: r.billingAddress!.name,
          street: r.billingAddress!.street);
    }).toList());
  }
}

class AccountInsertRequest {
  AccountInsertRequest({
    this.companyId,
    required this.firstName,
    required this.lastName,
    required this.location,
    this.billingAddress,
  });

  String? companyId;
  String firstName;
  String lastName;
  LatLng location;
  BillingAddress? billingAddress;
}

class AccountUpdateRequest {
  AccountUpdateRequest({
    this.companyId,
    required this.id,
    this.firstName,
    this.lastName,
    this.location,
    this.billingAddress,
  });

  String? companyId;
  int id;
  String? firstName;
  String? lastName;
  LatLng? location;
  BillingAddress? billingAddress;
}

class FullAccountViewQueryable extends KeyedViewQueryable<FullAccountView, int> {
  @override
  String get keyName => 'id';

  @override
  String encodeKey(int key) => TextEncoder.i.encode(key);

  @override
  String get query =>
      'SELECT "accounts".*, row_to_json("company".*) as "company", "invoices"."data" as "invoices", "parties"."data" as "parties", row_to_json("billingAddress".*) as "billingAddress"'
      'FROM "accounts"'
      'LEFT JOIN (${MemberCompanyViewQueryable().query}) "company"'
      'ON "accounts"."company_id" = "company"."id"'
      'LEFT JOIN ('
      '  SELECT "invoices"."account_id",'
      '    to_jsonb(array_agg("invoices".*)) as data'
      '  FROM (${OwnerInvoiceViewQueryable().query}) "invoices"'
      '  GROUP BY "invoices"."account_id"'
      ') "invoices"'
      'ON "accounts"."id" = "invoices"."account_id"'
      'LEFT JOIN ('
      '  SELECT "accounts_parties"."account_id",'
      '    to_jsonb(array_agg("parties".*)) as data'
      '  FROM "accounts_parties"'
      '  LEFT JOIN (${GuestPartyViewQueryable().query}) "parties"'
      '  ON "parties"."id" = "accounts_parties"."party_id"'
      '  GROUP BY "accounts_parties"."account_id"'
      ') "parties"'
      'ON "accounts"."id" = "parties"."account_id"'
      'LEFT JOIN (${BillingAddressQueryable().query}) "billingAddress"'
      'ON "accounts"."id" = "billingAddress"."account_id"';

  @override
  String get tableAlias => 'accounts';

  @override
  FullAccountView decode(TypedMap map) => FullAccountView(
      company: map.getOpt('company', MemberCompanyViewQueryable().decoder),
      invoices: map.getListOpt('invoices', OwnerInvoiceViewQueryable().decoder) ?? const [],
      parties: map.getListOpt('parties', GuestPartyViewQueryable().decoder) ?? const [],
      id: map.get('id', TextEncoder.i.decode),
      firstName: map.get('first_name', TextEncoder.i.decode),
      lastName: map.get('last_name', TextEncoder.i.decode),
      location: map.get('location', LatLngConverter().decode),
      billingAddress: map.getOpt('billingAddress', BillingAddressQueryable().decoder));
}

class FullAccountView {
  FullAccountView({
    this.company,
    required this.invoices,
    required this.parties,
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.location,
    this.billingAddress,
  });

  final MemberCompanyView? company;
  final List<OwnerInvoiceView> invoices;
  final List<GuestPartyView> parties;
  final int id;
  final String firstName;
  final String lastName;
  final LatLng location;
  final BillingAddress? billingAddress;
}

class UserAccountViewQueryable extends KeyedViewQueryable<UserAccountView, int> {
  @override
  String get keyName => 'id';

  @override
  String encodeKey(int key) => TextEncoder.i.encode(key);

  @override
  String get query =>
      'SELECT "accounts".*, row_to_json("company".*) as "company", "invoices"."data" as "invoices", "parties"."data" as "parties", row_to_json("billingAddress".*) as "billingAddress"'
      'FROM "accounts"'
      'LEFT JOIN (${MemberCompanyViewQueryable().query}) "company"'
      'ON "accounts"."company_id" = "company"."id"'
      'LEFT JOIN ('
      '  SELECT "invoices"."account_id",'
      '    to_jsonb(array_agg("invoices".*)) as data'
      '  FROM (${OwnerInvoiceViewQueryable().query}) "invoices"'
      '  GROUP BY "invoices"."account_id"'
      ') "invoices"'
      'ON "accounts"."id" = "invoices"."account_id"'
      'LEFT JOIN ('
      '  SELECT "accounts_parties"."account_id",'
      '    to_jsonb(array_agg("parties".*)) as data'
      '  FROM "accounts_parties"'
      '  LEFT JOIN (${GuestPartyViewQueryable().query}) "parties"'
      '  ON "parties"."id" = "accounts_parties"."party_id"'
      '  GROUP BY "accounts_parties"."account_id"'
      ') "parties"'
      'ON "accounts"."id" = "parties"."account_id"'
      'LEFT JOIN (${BillingAddressQueryable().query}) "billingAddress"'
      'ON "accounts"."id" = "billingAddress"."account_id"';

  @override
  String get tableAlias => 'accounts';

  @override
  UserAccountView decode(TypedMap map) => UserAccountView(
      company: map.getOpt('company', MemberCompanyViewQueryable().decoder),
      invoices: map.getListOpt('invoices', OwnerInvoiceViewQueryable().decoder) ?? const [],
      parties: map.getListOpt('parties', GuestPartyViewQueryable().decoder) ?? const [],
      id: map.get('id', TextEncoder.i.decode),
      firstName: map.get('first_name', TextEncoder.i.decode),
      lastName: map.get('last_name', TextEncoder.i.decode),
      location: map.get('location', LatLngConverter().decode),
      billingAddress: map.getOpt('billingAddress', BillingAddressQueryable().decoder));
}

class UserAccountView {
  UserAccountView({
    this.company,
    required this.invoices,
    required this.parties,
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.location,
    this.billingAddress,
  });

  final MemberCompanyView? company;
  final List<OwnerInvoiceView> invoices;
  final List<GuestPartyView> parties;
  final int id;
  final String firstName;
  final String lastName;
  final LatLng location;
  final BillingAddress? billingAddress;
}

class CompanyAccountViewQueryable extends KeyedViewQueryable<CompanyAccountView, int> {
  @override
  String get keyName => 'id';

  @override
  String encodeKey(int key) => TextEncoder.i.encode(key);

  @override
  String get query =>
      'SELECT "accounts".*, ${FilterByField('sponsor_id', '=', 'company_id').transform('parties', 'accounts')}'
      'FROM "accounts"'
      'LEFT JOIN ('
      '  SELECT "accounts_parties"."account_id",'
      '    to_jsonb(array_agg("parties".*)) as data'
      '  FROM "accounts_parties"'
      '  LEFT JOIN (${CompanyPartyViewQueryable().query}) "parties"'
      '  ON "parties"."id" = "accounts_parties"."party_id"'
      '  GROUP BY "accounts_parties"."account_id"'
      ') "parties"'
      'ON "accounts"."id" = "parties"."account_id"';

  @override
  String get tableAlias => 'accounts';

  @override
  CompanyAccountView decode(TypedMap map) => CompanyAccountView(
      parties: map.getListOpt('parties', CompanyPartyViewQueryable().decoder) ?? const [],
      id: map.get('id', TextEncoder.i.decode),
      firstName: map.get('first_name', TextEncoder.i.decode),
      lastName: map.get('last_name', TextEncoder.i.decode),
      location: map.get('location', LatLngConverter().decode));
}

class CompanyAccountView {
  CompanyAccountView({
    required this.parties,
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.location,
  });

  final List<CompanyPartyView> parties;
  final int id;
  final String firstName;
  final String lastName;
  final LatLng location;
}
